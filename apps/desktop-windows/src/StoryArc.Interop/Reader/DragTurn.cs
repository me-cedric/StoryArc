namespace StoryArc.Interop.Reader;

/// <summary>
/// Turning a page by dragging with the pointer (desktop-clients task 2.40, after 2.15;
/// desktop-experience "Dragging to turn a page"). A drag past the threshold commits a turn in the
/// direction of the drag, mirrored in a right-to-left publication; a drag short of it settles
/// back and no turn is counted. The threshold is the one iOS uses for a swipe
/// (<c>fadeSwipeThreshold</c>, 48 points).
/// </summary>
public static class DragTurn
{
    public const double Threshold = 48;

    /// <summary>
    /// The reading-order step a finished drag asks for: 1 for the next page, -1 for the previous,
    /// 0 for none. A drag toward the left (negative travel) shows what lies to the right of the
    /// page, which is the next page in left-to-right and the previous page in right-to-left.
    /// </summary>
    public static int ReadingStep(double travel, bool isRightToLeft)
    {
        var displayStep = travel <= -Threshold ? 1 : travel >= Threshold ? -1 : 0;
        return isRightToLeft ? -displayStep : displayStep;
    }

    /// <summary>
    /// How far a page follows the pointer during a drag, in the page's own pixels: the drag
    /// itself up to the window width, so a page never leaves the window before the release.
    /// </summary>
    public static double Travel(double pointerDelta, double viewportWidth) =>
        Math.Clamp(pointerDelta, -viewportWidth, viewportWidth);
}
