namespace StoryArc.Interop.Playback;

/// <summary>The buttons of the system media transport controls the app answers (<c>SystemMediaTransportControlsButton</c>).</summary>
public enum TransportButton
{
    Play,
    Pause,
    Stop,
    Next,
    Previous,
    FastForward,
    Rewind,
}

/// <summary>What the player does for a transport button or a seek; the player model carries it out.</summary>
public enum TransportAction
{
    None,
    Play,
    Pause,
    Stop,
    NextChapter,
    PreviousChapter,
    SkipForward,
    SkipBack,
}

/// <summary>
/// What the system overlay shows while a session exists (desktop-experience, "Media keys and system media
/// controls"): the title, the second line (the chapter, or the author where the publication declares
/// no navigation), the cover, and the timeline. A read-aloud session shows the same, which is the
/// spec's one set of actions for a listener to learn.
/// </summary>
/// <param name="CoverPath">A file the host turns into a thumbnail stream, or <c>null</c> for a publication with no cover.</param>
public sealed record TransportState(
    string Title,
    string Subtitle,
    string? CoverPath,
    TimeSpan Position,
    TimeSpan Duration,
    double Speed,
    bool IsPlaying,
    bool HasNext,
    bool HasPrevious);

/// <summary>
/// The system's transport controls behind an interface, so the rules test with a fake: on Windows it is
/// <c>SystemMediaTransportControls</c> and its <c>DisplayUpdater</c> and <c>UpdateTimelineProperties</c>.
/// </summary>
public interface ISystemTransport
{
    /// <summary>Puts the entry up, or refreshes it, with its state and enabled buttons.</summary>
    void Show(TransportState state);

    /// <summary>Takes the entry down: <c>IsEnabled = false</c> and the display cleared, so the keys go back to whoever else holds them.</summary>
    void Hide();
}

/// <summary>
/// Media keys and the system overlay as pure rules (desktop-clients task 4.19). An entry exists only
/// while a session exists and leaves when it ends or the app quits; while no session exists the app
/// never enables the controls, so another application's hold on the keys is left alone and the
/// app's own on-screen controls keep working. A press while the entry is down is ignored. A seek in
/// the overlay moves the playback. The timeline is refreshed on every position tick that the overlay
/// would show differently, which is once a second, not once a frame.
/// </summary>
public sealed class TransportControls
{
    private readonly ISystemTransport _system;
    private TransportState? _shown;

    public TransportControls(ISystemTransport system)
    {
        _system = system;
    }

    /// <summary>Whether the entry is up.</summary>
    public bool IsShown => _shown is not null;

    /// <summary>The session's state changed: the entry follows it, or leaves when the session ended.</summary>
    public void SessionChanged(PlaybackSession session, TransportState? state)
    {
        if (!session.IsActive || state is null)
        {
            if (_shown is not null)
            {
                _shown = null;
                _system.Hide();
            }

            return;
        }

        var next = state with { IsPlaying = session.IsPlaying };
        if (_shown is not null && _shown == next)
        {
            return;
        }

        _shown = next;
        _system.Show(next);
    }

    /// <summary>A position tick: the overlay is refreshed only when its second changes.</summary>
    public void PositionChanged(TimeSpan position)
    {
        if (_shown is null || (long)_shown.Position.TotalSeconds == (long)position.TotalSeconds)
        {
            return;
        }

        _shown = _shown with { Position = position };
        _system.Show(_shown);
    }

    /// <summary>The entry leaves at quit, whatever the session was doing.</summary>
    public void Quit()
    {
        if (_shown is not null)
        {
            _shown = null;
            _system.Hide();
        }
    }

    /// <summary>What a button press asks of the player; <see cref="TransportAction.None"/> while the entry is down.</summary>
    public TransportAction ButtonPressed(TransportButton button)
    {
        if (_shown is null)
        {
            return TransportAction.None;
        }

        return button switch
        {
            TransportButton.Play => TransportAction.Play,
            TransportButton.Pause => TransportAction.Pause,
            TransportButton.Stop => TransportAction.Stop,
            TransportButton.Next => _shown.HasNext ? TransportAction.NextChapter : TransportAction.None,
            TransportButton.Previous => _shown.HasPrevious ? TransportAction.PreviousChapter : TransportAction.None,
            TransportButton.FastForward => TransportAction.SkipForward,
            TransportButton.Rewind => TransportAction.SkipBack,
            _ => TransportAction.None,
        };
    }

    /// <summary>A seek in the overlay: the time to move to, inside the timeline, or <c>null</c> while the entry is down.</summary>
    public TimeSpan? SeekRequested(TimeSpan requested)
    {
        if (_shown is null)
        {
            return null;
        }

        return requested < TimeSpan.Zero ? TimeSpan.Zero : requested > _shown.Duration ? _shown.Duration : requested;
    }
}
