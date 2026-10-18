using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Dispatching;
using StoryArc.Interop.Playback;
using Windows.Media;
using Windows.Media.Audio;
using Windows.Media.Core;
using Windows.Media.Devices;
using Windows.Media.Playback;
using Windows.Media.SpeechSynthesis;
using Windows.Storage.Streams;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The one player of the app (desktop-clients tasks 4.19 and 4.20; design.md Decision 5b and
/// <c>docs/delivery/desktop-spike-audio-windows.md</c>): a <c>MediaPlayer</c> owned by the process, so
/// playback outlives every window, with <see cref="PlayerModel"/> deciding and this class doing. A
/// narrated book plays from its file; a voice reads a publication one synthesised sentence at a time
/// through the same player. The system's transport controls are driven by hand
/// (<c>CommandManager.IsEnabled = false</c>) through <see cref="TransportControls"/>, so the entry exists
/// only while a session does, and the system is kept from sleeping only while it plays.
/// </summary>
internal sealed class PlaybackService : IDisposable
{
    private readonly DispatcherQueue _dispatcher;
    private readonly Action<string, TimeSpan> _recordPosition;
    private readonly PlayerModel _model = new();
    private readonly PlaybackKeepAwake _keepAwake = new(Win32.SetThreadExecutionState);
    private MediaPlayer? _player;
    private TransportControls? _transport;
    private AudioStateMonitor? _monitor;
    private SpeechSynthesizer? _speech;
    private ReadAloudModel? _readAloud;
    private Action<Sentence?>? _followVoice;
    private WindowsTransport? _system;
    private (PlayerArtwork Artwork, string Path)? _coverlessArtwork;
    private TimeSpan _lastReported;
    private bool _isEnding;

    public PlaybackService(DispatcherQueue dispatcher, Action<string, TimeSpan> recordPosition)
    {
        _dispatcher = dispatcher;
        _recordPosition = recordPosition;
        _model.Changed += OnModelChanged;
        _model.SoughtTo += ApplySeek;
        _model.WriteDue += OnWriteDue;
    }

    /// <summary>Raised on the interface thread whenever the player's surfaces should redraw.</summary>
    public event Action? Changed;

    /// <summary>Raised once when a session ended because another publication opened, with the title that stopped.</summary>
    public event Action<string>? VoiceStopped;

    public PlayerModel Model => _model;

    /// <summary>Whether the system offers a voice at all; without one the read-aloud control is absent.</summary>
    public static bool HasVoice => SpeechSynthesizer.AllVoices.Count > 0;

    /// <summary>Plays the narrated book at <paramref name="path"/>: the chapters come from the file's chapter cues once it opens.</summary>
    public void PlayNarrated(string path, string title, string? author, string? coverPath, TimeSpan at)
    {
        var player = Player();
        EndReadAloud();
        var item = new MediaPlaybackItem(MediaSource.CreateFromUri(new Uri(path)));
        _pendingStart = () =>
        {
            var chapters = ChaptersOf(item);
            var duration = player.PlaybackSession.NaturalDuration;
            _model.Start(new PlaybackItem(path, title, author, coverPath, chapters, duration, PlaybackKind.Narrated), at);
            player.PlaybackSession.Position = _model.Position;
            player.PlaybackSession.PlaybackRate = _model.Speed;
            player.Play();
        };
        player.Source = item;
    }

    /// <summary>
    /// Reads <paramref name="queue"/> aloud from its first sentence; <paramref name="follow"/> is told each sentence as it starts,
    /// and <c>null</c> at the end, so the page can follow the voice and the highlight be withdrawn.
    /// </summary>
    public void ReadAloud(string publicationId, string title, string? author, ReadAloudModel queue, int chapterIndex, IReadOnlyList<PlaybackChapter> chapters, Action<Sentence?> follow)
    {
        if (!queue.IsAvailable)
        {
            return;
        }

        var player = Player();
        _speech ??= new SpeechSynthesizer();
        _readAloud = queue;
        _followVoice = follow;
        _model.Start(new PlaybackItem(publicationId, title, author, null, chapters, TimeSpan.FromSeconds(Math.Max(1, chapters.Count)), PlaybackKind.ReadAloud), TimeSpan.FromSeconds(chapterIndex));
        _ = SpeakAsync(queue.Start(chapterIndex));
        player.PlaybackSession.PlaybackRate = 1;
    }

    public void TogglePlayPause() => _model.TogglePlayPause();

    public void SkipBack() => _model.SkipBack();

    public void SkipForward() => _model.SkipForward();

    public void Stop() => _model.Stop();

    /// <summary>
    /// A seek from the scrub control or a chapter row: the model and the engine move together. <paramref name="settled"/> is false
    /// while the scrub control is still dragged, so the position is written once, when it is let go (<see cref="SeekSettled"/>).
    /// </summary>
    public void SeekTo(TimeSpan to, bool settled = true) => _model.Seek(to, settled);

    /// <summary>The listener let go of the scrub control.</summary>
    public void SeekSettled() => _model.SeekSettled();

    /// <summary>
    /// The coverless well the player window drew, as the artwork of the system's media controls for a book with no cover
    /// (audio-playback, "A publication with no cover"): the lock screen gets the same artwork, not a second one.
    /// </summary>
    public void UseCoverlessArtwork(PlayerArtwork artwork, string path)
    {
        _coverlessArtwork = (artwork, path);
        if (CoverlessPath() is { } shown && _model.IsActive)
        {
            _system?.ShowThumbnail(shown);
        }
    }

    /// <summary>The rendered well, when it is the one of the book playing now and the book has no cover of its own.</summary>
    private string? CoverlessPath() =>
        _model.Item is { CoverPath: null } item && _coverlessArtwork is { } rendered && rendered.Artwork == PlayerArtwork.Of(item) ? rendered.Path : null;

    /// <summary>
    /// The chapters and the length of the narrated book at <paramref name="path"/>, read before it plays, for its publication's
    /// page; <c>null</c> when the system cannot open it. A muted engine of its own, kept off the system's media controls.
    /// </summary>
    public static async Task<(IReadOnlyList<PlaybackChapter> Chapters, TimeSpan Duration)?> ReadChaptersAsync(string path)
    {
        using var player = new MediaPlayer { AutoPlay = false, IsMuted = true };
        player.CommandManager.IsEnabled = false;
        var opened = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        player.MediaOpened += (sender, args) => opened.TrySetResult(true);
        player.MediaFailed += (sender, args) => opened.TrySetResult(false);
        var item = new MediaPlaybackItem(MediaSource.CreateFromUri(new Uri(path)));
        player.Source = item;
        try
        {
            if (!await opened.Task.WaitAsync(TimeSpan.FromSeconds(10)))
            {
                return null;
            }
        }
        catch (TimeoutException)
        {
            return null;
        }

        return (ChaptersOf(item), player.PlaybackSession.NaturalDuration);
    }

    /// <summary>The chapter markers of an opened item, in order.</summary>
    private static List<PlaybackChapter> ChaptersOf(MediaPlaybackItem item) => item.TimedMetadataTracks
        .Where(track => track.TimedMetadataKind == TimedMetadataKind.Chapter)
        .SelectMany(track => track.Cues.OfType<ChapterCue>())
        .OrderBy(cue => cue.StartTime)
        .Select(cue => new PlaybackChapter(cue.Title, cue.StartTime, cue.Duration))
        .ToList();

    /// <summary>A moment to write the listening position: read from the engine itself, never from what a surface last drew.</summary>
    private void OnWriteDue()
    {
        if (_model.Item is { Kind: PlaybackKind.Narrated } item && _player is { } player)
        {
            _recordPosition(item.PublicationId, player.PlaybackSession.Position);
        }
    }

    /// <summary>Quit: the entry leaves the system's controls whatever the session was doing, and the position is recorded.</summary>
    public void Quit()
    {
        if (_model.IsActive)
        {
            _model.Stop();
        }

        _transport?.Quit();
    }

    public void Dispose()
    {
        Quit();
        _monitor = null;
        _speech?.Dispose();
        _player?.Dispose();
        _player = null;
    }

    private Action? _pendingStart;

    private MediaPlayer Player()
    {
        if (_player is not null)
        {
            return _player;
        }

        var player = new MediaPlayer
        {
            AudioCategory = MediaPlayerAudioCategory.Media,
            AutoPlay = false,
        };
        player.CommandManager.IsEnabled = false;
        player.MediaOpened += (sender, args) => OnInterface(() =>
        {
            var start = _pendingStart;
            _pendingStart = null;
            start?.Invoke();
        });
        player.MediaEnded += (sender, args) => OnInterface(OnMediaEnded);
        player.MediaFailed += (sender, args) => OnInterface(() => _model.Stop());
        player.PlaybackSession.PositionChanged += (session, args) =>
        {
            var position = session.Position;
            OnInterface(() => OnPosition(position));
        };

        var controls = player.SystemMediaTransportControls;
        controls.ButtonPressed += (sender, args) => OnInterface(() => _model.Do(_transport?.ButtonPressed(Map(args.Button)) ?? TransportAction.None));
        controls.PlaybackPositionChangeRequested += (sender, args) => OnInterface(() =>
        {
            if (_transport?.SeekRequested(args.RequestedPlaybackPosition) is { } to)
            {
                _model.Seek(to);
                ApplySeek(to);
            }
        });
        _system = new WindowsTransport(controls, CoverlessPath);
        _transport = new TransportControls(_system);

        // Something else taking the audio, and the headphones going: the two events the spike page names.
        try
        {
            _monitor = AudioStateMonitor.CreateForRenderMonitoring(global::Windows.Media.Render.AudioRenderCategory.Media);
            _monitor.SoundLevelChanged += (monitor, args) =>
            {
                var level = monitor.SoundLevel;
                OnInterface(() =>
                {
                    if (level == SoundLevel.Full)
                    {
                        _model.InterruptionEnded(mayResume: true);
                    }
                    else
                    {
                        _model.Interrupted();
                    }
                });
            };
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            _monitor = null;
        }

        MediaDevice.DefaultAudioRenderDeviceChanged += (sender, args) => OnInterface(_model.RouteLost);
        _player = player;
        return player;
    }

    private void OnModelChanged()
    {
        var player = _player;
        if (player is not null)
        {
            if (_model.Session.IsPlaying && player.PlaybackSession.PlaybackState != MediaPlaybackState.Playing && _pendingStart is null)
            {
                player.Play();
            }
            else if (!_model.Session.IsPlaying && player.PlaybackSession.PlaybackState == MediaPlaybackState.Playing)
            {
                player.Pause();
            }

            player.Volume = _model.Gain;
            if (_model.Item?.Kind == PlaybackKind.Narrated && Math.Abs(player.PlaybackSession.PlaybackRate - _model.Speed) > 0.001)
            {
                player.PlaybackSession.PlaybackRate = _model.Speed;
            }
            else if (_speech is not null && _model.Item?.Kind == PlaybackKind.ReadAloud)
            {
                _speech.Options.SpeakingRate = PlaybackSpeed.SpeakingRate(_model.Speed);
            }
        }

        _keepAwake.SessionChanged(_model.Session);
        _transport?.SessionChanged(_model.Session, _model.Transport());

        if (!_model.IsActive && !_isEnding && _model.LastEnd != EndReason.None && _model.Item is { } ended)
        {
            _isEnding = true;
            try
            {
                player?.Pause();
                if (_model.LastRecordedPosition is { } recorded)
                {
                    _recordPosition(ended.PublicationId, recorded);
                }

                if (_model.LastEnd == EndReason.Displaced)
                {
                    VoiceStopped?.Invoke(ended.Title);
                }

                _followVoice?.Invoke(null);
                if (ended.Kind == PlaybackKind.ReadAloud)
                {
                    EndReadAloud();
                }
            }
            finally
            {
                _isEnding = false;
            }
        }

        Changed?.Invoke();
    }

    private void OnPosition(TimeSpan position)
    {
        if (_model.Item?.Kind != PlaybackKind.Narrated)
        {
            return;
        }

        var elapsed = position > _lastReported ? position - _lastReported : TimeSpan.Zero;
        _lastReported = position;
        _model.PositionReported(position, elapsed);
        _transport?.PositionChanged(position);
    }

    /// <summary>A narrated book reached its end, or the voice finished a sentence.</summary>
    private void OnMediaEnded()
    {
        if (_model.Item?.Kind == PlaybackKind.ReadAloud && _readAloud is { } queue)
        {
            var next = queue.Next();
            if (next is null)
            {
                _model.Stop();
                return;
            }

            _model.PositionReported(TimeSpan.FromSeconds(next.ChapterIndex), SleepCountdown.Tick);
            _ = SpeakAsync(next);
            return;
        }

        _model.Stop();
    }

    private async Task SpeakAsync(Sentence? sentence)
    {
        if (sentence is null || _speech is null || _player is null)
        {
            _model.Stop();
            return;
        }

        _followVoice?.Invoke(sentence);
        try
        {
            var stream = await _speech.SynthesizeTextToStreamAsync(sentence.Text);
            if (_model.Item?.Kind != PlaybackKind.ReadAloud)
            {
                return;
            }

            _player.Source = MediaSource.CreateFromStream(stream, stream.ContentType);
            if (_model.Session.IsPlaying)
            {
                _player.Play();
            }
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException or ArgumentException)
        {
            // The voice refused this sentence: skip it rather than stop the book.
            OnMediaEnded();
        }
    }

    private void ApplySeek(TimeSpan to)
    {
        if (_player is { } player && _model.Item?.Kind == PlaybackKind.Narrated)
        {
            player.PlaybackSession.Position = to;
        }
    }

    private void EndReadAloud()
    {
        _readAloud = null;
        _followVoice = null;
    }

    private void OnInterface(Action action)
    {
        if (!_dispatcher.TryEnqueue(() => action()))
        {
            // The queue is shutting down: nothing left to draw.
        }
    }

    private static TransportButton Map(SystemMediaTransportControlsButton button) => button switch
    {
        SystemMediaTransportControlsButton.Play => TransportButton.Play,
        SystemMediaTransportControlsButton.Pause => TransportButton.Pause,
        SystemMediaTransportControlsButton.Stop => TransportButton.Stop,
        SystemMediaTransportControlsButton.Next => TransportButton.Next,
        SystemMediaTransportControlsButton.Previous => TransportButton.Previous,
        SystemMediaTransportControlsButton.FastForward => TransportButton.FastForward,
        _ => TransportButton.Rewind,
    };

    /// <summary>The real transport: <c>SystemMediaTransportControls</c> with its display updater and timeline.</summary>
    private sealed class WindowsTransport : ISystemTransport
    {
        private readonly SystemMediaTransportControls _controls;
        private readonly Func<string?> _coverless;

        public WindowsTransport(SystemMediaTransportControls controls, Func<string?> coverless)
        {
            _controls = controls;
            _coverless = coverless;
        }

        /// <summary>The artwork alone, for a well rendered after the entry was shown.</summary>
        public void ShowThumbnail(string path)
        {
            if (!_controls.IsEnabled)
            {
                return;
            }

            _controls.DisplayUpdater.Thumbnail = Thumbnail(path);
            _controls.DisplayUpdater.Update();
        }

        private static RandomAccessStreamReference? Thumbnail(string? path) =>
            path is not null && File.Exists(path) ? RandomAccessStreamReference.CreateFromStream(File.OpenRead(path).AsRandomAccessStream()) : null;

        public void Show(TransportState state)
        {
            _controls.IsEnabled = true;
            _controls.IsPlayEnabled = true;
            _controls.IsPauseEnabled = true;
            _controls.IsStopEnabled = true;
            _controls.IsNextEnabled = state.HasNext;
            _controls.IsPreviousEnabled = state.HasPrevious;
            _controls.IsFastForwardEnabled = true;
            _controls.IsRewindEnabled = true;
            _controls.PlaybackStatus = state.IsPlaying ? MediaPlaybackStatus.Playing : MediaPlaybackStatus.Paused;
            _controls.PlaybackRate = state.Speed;

            var updater = _controls.DisplayUpdater;
            updater.Type = MediaPlaybackType.Music;
            updater.MusicProperties.Title = state.Title;
            updater.MusicProperties.Artist = state.Subtitle;
            updater.Thumbnail = Thumbnail(state.CoverPath ?? _coverless());
            updater.Update();

            _controls.UpdateTimelineProperties(new SystemMediaTransportControlsTimelineProperties
            {
                StartTime = TimeSpan.Zero,
                MinSeekTime = TimeSpan.Zero,
                Position = state.Position,
                MaxSeekTime = state.Duration,
                EndTime = state.Duration,
            });
        }

        public void Hide()
        {
            _controls.DisplayUpdater.ClearAll();
            _controls.PlaybackStatus = MediaPlaybackStatus.Closed;
            _controls.IsEnabled = false;
        }
    }
}
