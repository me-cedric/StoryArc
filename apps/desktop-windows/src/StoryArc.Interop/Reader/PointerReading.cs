namespace StoryArc.Interop.Reader;

/// <summary>
/// The chrome and the pointer in a reader, driven by a clock the host supplies (desktop-clients
/// task 2.39, after 2.12; desktop-experience "Pointer reading"). Moving the pointer reveals the
/// chrome; after the pointer rests for three seconds the chrome and the pointer hide, and the
/// page does not move. Keyboard focus in the chrome keeps it: tabbing into a hidden bar reveals
/// it and a bar that holds focus never hides under a reader's hands.
/// </summary>
public sealed class HoverChrome
{
    /// <summary>How long the pointer rests before the chrome and the pointer hide.</summary>
    public static readonly TimeSpan RestDelay = TimeSpan.FromSeconds(3);

    private TimeSpan _lastMovement = TimeSpan.MinValue;
    private bool _isPointerInside;
    private bool _isFocusInChrome;

    public bool IsChromeVisible { get; private set; }

    public bool IsPointerHidden { get; private set; }

    /// <summary>When the next <see cref="Settle"/> may hide the chrome, or <c>null</c> while nothing is due.</summary>
    public TimeSpan? HideDueAt => IsChromeVisible && _isPointerInside && !_isFocusInChrome ? _lastMovement + RestDelay : null;

    public void PointerMoved(TimeSpan now)
    {
        _isPointerInside = true;
        _lastMovement = now;
        IsChromeVisible = true;
        IsPointerHidden = false;
    }

    /// <summary>The pointer left the window: the pointer shows again, the chrome stays until the reader asks.</summary>
    public void PointerLeft()
    {
        _isPointerInside = false;
        IsPointerHidden = false;
    }

    /// <summary>A click in the middle of the page, or the one key that toggles the chrome.</summary>
    public void Toggle(TimeSpan now)
    {
        IsChromeVisible = !IsChromeVisible;
        _lastMovement = now;
        IsPointerHidden = false;
    }

    /// <summary>Keyboard focus moved into the chrome (true) or back to the page (false).</summary>
    public void FocusInChrome(bool isInChrome, TimeSpan now)
    {
        _isFocusInChrome = isInChrome;
        if (isInChrome)
        {
            IsChromeVisible = true;
            IsPointerHidden = false;
        }
        else
        {
            _lastMovement = now;
        }
    }

    /// <summary>
    /// The host's timer tick. Hides the chrome and the pointer once the pointer has rested for the
    /// delay; returns whether anything changed so the host redraws only then.
    /// </summary>
    public bool Settle(TimeSpan now)
    {
        if (HideDueAt is not { } due || now < due)
        {
            return false;
        }

        IsChromeVisible = false;
        IsPointerHidden = true;
        return true;
    }
}

/// <summary>
/// What a click on the page asks for, by where it landed (desktop-experience "Edge click zones";
/// design.md Open Question 2: the zones are on by default, as on a phone). Each edge zone is a
/// third of the width, leaving the middle third to the chrome. A click on the leading edge turns
/// back and on the trailing edge forward, so the zones mirror in a right-to-left publication.
/// With the zones off a click anywhere toggles the chrome and no click turns a page.
/// </summary>
public static class EdgeClickZones
{
    public const double EdgeFraction = 1.0 / 3.0;

    public static PageAction Resolve(double x, double width, bool isRightToLeft, bool zonesOn)
    {
        if (!zonesOn || width <= 0)
        {
            return PageAction.ToggleChrome;
        }

        var edge = width * EdgeFraction;
        if (x < edge)
        {
            return isRightToLeft ? PageAction.Next : PageAction.Previous;
        }

        if (x > width - edge)
        {
            return isRightToLeft ? PageAction.Previous : PageAction.Next;
        }

        return PageAction.ToggleChrome;
    }
}
