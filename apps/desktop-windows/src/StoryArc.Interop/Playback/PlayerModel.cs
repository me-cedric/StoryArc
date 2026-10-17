using System.Globalization;

namespace StoryArc.Interop.Playback;

/// <summary>What is playing: a narrated book or a voice reading a publication; both take the one player (audio-playback, "One player for everything that speaks").</summary>
public enum PlaybackKind
{
    Narrated,
    ReadAloud,
}

/// <summary>The publication the player was given.</summary>
/// <param name="Author">Shown on the second line where the publication declares no chapters.</param>
public sealed record PlaybackItem(string PublicationId, string Title, string? Author, string? CoverPath, IReadOnlyList<PlaybackChapter> Chapters, TimeSpan Duration, PlaybackKind Kind);

/// <summary>How a chapter row is marked (audio-playback, "Chapters").</summary>
public enum ChapterMark
{
    NotReached,
    InProgress,
    Finished,
}

/// <summary>One row of the chapter list, with everything a screen reader hears as one control.</summary>
public sealed record ChapterRow(int Index, string Title, TimeSpan Duration, ChapterMark Mark, TimeSpan? Remaining);

/// <summary>Why the session ended, for the one-line notice the spec asks for in some cases.</summary>
public enum EndReason
{
    None,

    /// <summary>The listener stopped it, or the publication ran out: no notice.</summary>
    Stopped,

    /// <summary>The sleep timer elapsed: the recorded position sits a little before the fade's end.</summary>
    SleepTimer,

    /// <summary>Audio was taken for good: the position is recorded and the transport leaves.</summary>
    AudioLost,

    /// <summary>A different publication opened: told once, rather than discovered by silence.</summary>
    Displaced,
}

/// <summary>
/// The player's view model (desktop-clients task 4.20), engine-free: the Windows code feeds it the
/// engine's position and events and does what its properties say. It holds the session state, the
/// speed, the skips, the sleep countdown with its fade, the chapter list with its marks, the
/// transport state the system overlay shows, and the end of a session with its reason and the
/// position to record. Every method is safe on the interface thread.
/// </summary>
public sealed class PlayerModel
{
    private SleepCountdown? _sleep;

    /// <summary>Raised whenever something a surface shows changed.</summary>
    public event Action? Changed;

    public PlaybackSession Session { get; private set; } = new();

    public PlaybackItem? Item { get; private set; }

    public TimeSpan Position { get; private set; }

    public double Speed { get; private set; } = PlaybackSpeed.Normal;

    /// <summary>How loud the engine should play, 0 to 1: full, or inside the sleep timer's fade.</summary>
    public double Gain { get; private set; } = 1;

    public SleepCountdown? Sleep => _sleep;

    /// <summary>Why the last session ended; <see cref="EndReason.None"/> while one runs.</summary>
    public EndReason LastEnd { get; private set; }

    /// <summary>The position the last session recorded when it ended.</summary>
    public TimeSpan? LastRecordedPosition { get; private set; }

    public bool IsActive => Session.IsActive;

    public int? CurrentChapter => Item is null ? null : Skips.ChapterAt(Item.Chapters, Position);

    /// <summary>
    /// Starts <paramref name="item"/> at <paramref name="at"/>. A session already running on another publication ends first at its
    /// position, as <see cref="EndReason.Displaced"/>, so the listener is told once (read-aloud, "Opening a different publication").
    /// </summary>
    public void Start(PlaybackItem item, TimeSpan at, double? speed = null)
    {
        var displaced = Item is not null && Item.PublicationId != item.PublicationId && Session.IsActive;
        if (displaced)
        {
            End(EndReason.Displaced, Position);
        }

        Item = item;
        Position = Clamp(at);
        Speed = PlaybackSpeed.Clamp(speed ?? Speed);
        Gain = 1;
        _sleep = null;
        LastEnd = displaced ? EndReason.Displaced : EndReason.None;
        Session = Session.Started();
        Notify();
    }

    public void TogglePlayPause()
    {
        if (Session.IsPlaying)
        {
            Pause();
        }
        else if (Session.IsActive)
        {
            Resume();
        }
    }

    public void Pause() => Apply(Session.PausedByListener());

    public void Resume() => Apply(Session.Resumed());

    /// <summary>The listener stopped it, or the publication ran out of words or audio.</summary>
    public void Stop() => End(EndReason.Stopped, Position);

    /// <summary>Something else took the audio.</summary>
    public void Interrupted() => Apply(Session.Interrupted());

    /// <summary>The audio came back; <paramref name="mayResume"/> is what the platform said.</summary>
    public void InterruptionEnded(bool mayResume)
    {
        switch (Session.EndingInterruption(mayResume))
        {
            case InterruptionOutcome.Resume:
                Apply(Session.Resumed());
                break;
            case InterruptionOutcome.Lost:
                End(EndReason.AudioLost, Position);
                break;
        }
    }

    /// <summary>Headphones were removed: pause as the listener would have, so nothing resumes by itself when they return.</summary>
    public void RouteLost()
    {
        if (Session.IsPlaying)
        {
            Pause();
        }
    }

    /// <summary>The engine's position, several times a second. The sleep countdown and the fade follow it.</summary>
    public void PositionReported(TimeSpan position, TimeSpan elapsedSinceLastReport)
    {
        if (!Session.IsActive)
        {
            return;
        }

        Position = Clamp(position);
        if (_sleep is { } sleep && Session.IsPlaying)
        {
            _sleep = sleep.Advanced(elapsedSinceLastReport, UntilChapterEnd());
            Gain = _sleep.Gain(Item?.Kind == PlaybackKind.ReadAloud ? SleepCountdown.VoiceFade : null);
            if (_sleep.HasElapsed)
            {
                End(EndReason.SleepTimer, SleepCountdown.RecordedPosition(Position));
                return;
            }
        }

        Notify();
    }

    public void Seek(TimeSpan to)
    {
        Position = Clamp(to);
        Notify();
    }

    public void SkipBack() => Seek(Skips.Apply(Position, -Skips.Back, Item?.Duration ?? TimeSpan.Zero));

    public void SkipForward() => Seek(Skips.Apply(Position, Skips.Forward, Item?.Duration ?? TimeSpan.Zero));

    public void NextChapter()
    {
        if (Item is { } item && CurrentChapter is { } current && current + 1 < item.Chapters.Count)
        {
            Seek(item.Chapters[current + 1].Start);
        }
    }

    public void PreviousChapter()
    {
        if (Item is { } item && CurrentChapter is { } current)
        {
            // Decided before the seek: inside a chapter, back to its start; at its start, back
            // to the chapter before (a seek to the start must not then count as "at the start").
            var atStart = current > 0 && Position == item.Chapters[current].Start;
            Seek(item.Chapters[atStart ? current - 1 : current].Start);
        }
    }

    public void SetSpeed(double rate)
    {
        Speed = PlaybackSpeed.Clamp(rate);
        Notify();
    }

    /// <summary>Sets or clears the sleep timer. End of chapter with no chapter to end is not set, and <see cref="Sleep"/> stays <c>null</c>.</summary>
    public void SetSleep(SleepTimer? timer)
    {
        _sleep = timer is null ? null : SleepCountdown.Of(timer, UntilChapterEnd());
        Gain = _sleep?.Gain() ?? 1;
        Notify();
    }

    /// <summary>Carries out what the transport asked (task 4.19 onto 4.20).</summary>
    public void Do(TransportAction action)
    {
        switch (action)
        {
            case TransportAction.Play:
                Resume();
                break;
            case TransportAction.Pause:
                Pause();
                break;
            case TransportAction.Stop:
                Stop();
                break;
            case TransportAction.NextChapter:
                NextChapter();
                break;
            case TransportAction.PreviousChapter:
                PreviousChapter();
                break;
            case TransportAction.SkipForward:
                SkipForward();
                break;
            case TransportAction.SkipBack:
                SkipBack();
                break;
        }
    }

    /// <summary>What the system overlay shows, or <c>null</c> when nothing plays.</summary>
    public TransportState? Transport()
    {
        if (Item is not { } item || !Session.IsActive)
        {
            return null;
        }

        var chapter = CurrentChapter;
        var subtitle = chapter is { } index ? item.Chapters[index].Title : item.Author ?? string.Empty;
        return new TransportState(
            item.Title,
            subtitle,
            item.CoverPath,
            Position,
            item.Duration,
            Speed,
            Session.IsPlaying,
            HasNext: chapter is { } next && next + 1 < item.Chapters.Count,
            HasPrevious: chapter is not null);
    }

    /// <summary>The chapter list with each row's mark and, for the one in progress, how much of it is left.</summary>
    public IReadOnlyList<ChapterRow> ChapterRows()
    {
        if (Item is not { } item)
        {
            return [];
        }

        var current = CurrentChapter;
        return item.Chapters.Select((chapter, index) =>
        {
            var mark = index == current ? ChapterMark.InProgress : chapter.End <= Position ? ChapterMark.Finished : ChapterMark.NotReached;
            TimeSpan? remaining = mark == ChapterMark.InProgress ? chapter.End - Position : null;
            return new ChapterRow(index, chapter.Title, chapter.Duration, mark, remaining);
        }).ToList();
    }

    /// <summary>The compact bar's one line: the publication and the chapter, as the system overlay shows them.</summary>
    public string? CompactLine(string pairFormat) =>
        Transport() is { } state ? state.Subtitle.Length == 0 ? state.Title : string.Format(CultureInfo.CurrentCulture, pairFormat, state.Title, state.Subtitle) : null;

    /// <summary>A time as the scrub control and the position label state it: <c>m:ss</c>, or <c>h:mm:ss</c> past an hour.</summary>
    public static string Clock(TimeSpan time)
    {
        var whole = time < TimeSpan.Zero ? TimeSpan.Zero : time;
        return whole.TotalHours >= 1
            ? string.Create(CultureInfo.InvariantCulture, $"{(int)whole.TotalHours}:{whole.Minutes:00}:{whole.Seconds:00}")
            : string.Create(CultureInfo.InvariantCulture, $"{whole.Minutes}:{whole.Seconds:00}");
    }

    private TimeSpan? UntilChapterEnd() =>
        Item is { } item && CurrentChapter is { } index ? item.Chapters[index].End - Position : null;

    private TimeSpan Clamp(TimeSpan at)
    {
        var total = Item?.Duration ?? TimeSpan.Zero;
        return at < TimeSpan.Zero ? TimeSpan.Zero : at > total ? total : at;
    }

    private void Apply(PlaybackSession next)
    {
        if (next == Session)
        {
            return;
        }

        Session = next;
        Notify();
    }

    private void End(EndReason reason, TimeSpan recorded)
    {
        LastEnd = reason;
        LastRecordedPosition = recorded;
        _sleep = null;
        Gain = 1;
        Session = Session.Stopped();
        Notify();
    }

    private void Notify() => Changed?.Invoke();
}
