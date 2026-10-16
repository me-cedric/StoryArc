namespace StoryArc.Interop.Reader;

/// <summary>What a full screen request changed.</summary>
public enum FullScreenChange
{
    None,
    Entered,
    Left,
}

/// <summary>
/// Whether a reader window is in full screen (desktop-clients task 2.41; desktop-experience "Full
/// screen reading"). The host asks the system whether it can grant full screen and tells this
/// model; a refusal leaves the window as it is and greys the menu entry, and leaving always works.
/// While in full screen the title bar and the chrome hide, and the pointer brings the chrome back
/// through <see cref="HoverChrome"/>.
/// </summary>
public sealed class FullScreenState
{
    public FullScreenState(bool isSupported)
    {
        IsAvailable = isSupported;
    }

    public bool IsFullScreen { get; private set; }

    /// <summary>False once the system has refused: the entry shows grey and says full screen is not available.</summary>
    public bool IsAvailable { get; private set; }

    /// <summary>The full screen key or menu entry.</summary>
    public FullScreenChange Toggle()
    {
        if (IsFullScreen)
        {
            IsFullScreen = false;
            return FullScreenChange.Left;
        }

        if (!IsAvailable)
        {
            return FullScreenChange.None;
        }

        IsFullScreen = true;
        return FullScreenChange.Entered;
    }

    /// <summary>Escape leaves full screen and is nothing in a window.</summary>
    public FullScreenChange Escape() => IsFullScreen ? Toggle() : FullScreenChange.None;

    /// <summary>The system did not grant what <see cref="Toggle"/> asked for: back to the window, and the entry goes grey.</summary>
    public void Refused()
    {
        IsFullScreen = false;
        IsAvailable = false;
    }
}
