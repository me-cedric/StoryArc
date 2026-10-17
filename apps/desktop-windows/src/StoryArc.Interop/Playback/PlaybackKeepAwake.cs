using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Playback;

/// <summary>
/// Stops the system idling into sleep while audio plays, and lets it once playback stops or pauses
/// (desktop-experience, "Keeping the display awake while reading", the Listening scenario; task 4.20).
/// <c>ES_CONTINUOUS | ES_SYSTEM_REQUIRED</c> through <c>SetThreadExecutionState</c>, on the thread the
/// player owns; the display may still sleep, because a listener does not look at it. A refusal is silent.
/// </summary>
public sealed class PlaybackKeepAwake
{
    private readonly Func<uint, uint> _setThreadExecutionState;

    public PlaybackKeepAwake(Func<uint, uint> setThreadExecutionState)
    {
        _setThreadExecutionState = setThreadExecutionState;
    }

    public bool IsHeld { get; private set; }

    /// <summary>Holds while the session plays and releases the moment it pauses, is interrupted or ends. Asking twice asks once.</summary>
    public void SessionChanged(PlaybackSession session)
    {
        if (session.IsPlaying == IsHeld)
        {
            return;
        }

        if (session.IsPlaying)
        {
            IsHeld = _setThreadExecutionState(DisplayKeepAwake.EsContinuous | DisplayKeepAwake.EsSystemRequired) != 0;
        }
        else
        {
            _setThreadExecutionState(DisplayKeepAwake.EsContinuous);
            IsHeld = false;
        }
    }
}
