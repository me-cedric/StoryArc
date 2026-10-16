namespace StoryArc.Interop.SystemSettings;

/// <summary>
/// Keeps the display awake while a reader window is in front (desktop-clients task 2.46;
/// desktop-experience "Keeping the display awake while reading"), through the Win32
/// <c>SetThreadExecutionState</c> of <c>kernel32.dll</c> (winbase.h). The flags are the
/// documented values: <c>ES_CONTINUOUS</c> 0x80000000 keeps the state until the next continuous
/// call, <c>ES_DISPLAY_REQUIRED</c> 0x00000002 resets the display idle timer, and
/// <c>ES_SYSTEM_REQUIRED</c> 0x00000001 resets the system idle timer (for audio, wave 4). The
/// function returns the previous state, or zero when it fails; a refusal is silent here, and
/// reading continues as usual (desktop-experience, "A system that cannot be asked").
/// </summary>
/// <remarks>
/// The P/Invoke lives in the Windows app; this class takes the call as a delegate so the wrapper
/// tests on any host and the app passes the real function.
/// </remarks>
public sealed class DisplayKeepAwake
{
    public const uint EsContinuous = 0x80000000;
    public const uint EsSystemRequired = 0x00000001;
    public const uint EsDisplayRequired = 0x00000002;

    private readonly Func<uint, uint> _setThreadExecutionState;

    public DisplayKeepAwake(Func<uint, uint> setThreadExecutionState)
    {
        _setThreadExecutionState = setThreadExecutionState;
    }

    /// <summary>Whether the system granted the last request to keep the display on.</summary>
    public bool IsHeld { get; private set; }

    /// <summary>Whether the system refused a request since the last release. Nothing alarming is shown for it.</summary>
    public bool WasRefused { get; private set; }

    /// <summary>Asks the system to keep the display on until <see cref="Release"/>. Asking twice asks once.</summary>
    public void Hold()
    {
        if (IsHeld)
        {
            return;
        }

        var previous = _setThreadExecutionState(EsContinuous | EsDisplayRequired);
        IsHeld = previous != 0;
        WasRefused = previous == 0;
    }

    /// <summary>Lets the display sleep again within the system's normal delay. Releasing what was never held is a no-op.</summary>
    public void Release()
    {
        if (IsHeld)
        {
            _setThreadExecutionState(EsContinuous);
        }

        IsHeld = false;
        WasRefused = false;
    }

    /// <summary>Holds while the reader window is in front and releases as soon as it is not.</summary>
    public void WindowIsInFront(bool isInFront)
    {
        if (isInFront)
        {
            Hold();
        }
        else
        {
            Release();
        }
    }
}
