namespace StoryArc.Interop.Reader;

/// <summary>A width and a height in device-independent pixels.</summary>
public readonly record struct Extent(double Width, double Height)
{
    public static Extent Zero { get; } = new(0, 0);
}

/// <summary>
/// How a page is fitted when it opens. Mirrors StoryArcKit's <c>PageFit</c>: every mode is a
/// multiple of fit-to-screen, which is what lets the wheel, a double click and the fit commands
/// share one number.
/// </summary>
public enum PageFit
{
    Screen,
    Width,
    Height,
    Original,
}

/// <summary>
/// The zoom arithmetic of the comic reader, mirrored from StoryArcKit's <c>PageFitting.swift</c>
/// and <c>PageFit.scale</c> so the limits are the ones a reader has for touch (desktop-clients task
/// 2.40, after 2.13; desktop-experience "Zoom and pan with a pointer"). Scale 1 is fit-to-screen;
/// the ceiling is the scroll view's maximum on iOS. A step beyond a limit returns the same scale
/// and the caller does nothing and says nothing.
/// </summary>
public static class PageZoom
{
    /// <summary>How far a page may be magnified, as a multiple of fit-to-screen (iOS <c>OwedFit.zoomCeiling</c>).</summary>
    public const double Ceiling = 6;

    /// <summary>The floor: never below fit-to-screen.</summary>
    public const double Floor = 1;

    /// <summary>What a double click zooms in to, as a multiple of the chosen fit (iOS <c>zoomedScale</c>).</summary>
    public const double DoubleClickFactor = 2.5;

    /// <summary>What one key press or one wheel notch with Control held multiplies the scale by.</summary>
    public const double StepFactor = 1.25;

    /// <summary>The page's size on screen at fit-to-screen, which every mode is a multiple of.</summary>
    public static Extent Fitted(Extent image, Extent viewport)
    {
        if (image.Width <= 0 || image.Height <= 0)
        {
            return Extent.Zero;
        }

        var scale = Math.Min(viewport.Width / image.Width, viewport.Height / image.Height);
        return new Extent(image.Width * scale, image.Height * scale);
    }

    /// <summary>The chosen fit's own scale: what a double click goes back to and what a step is measured from.</summary>
    public static double FitScale(PageFit mode, Extent image, Extent viewport)
    {
        var fitted = Fitted(image, viewport);
        if (fitted.Width <= 0 || fitted.Height <= 0)
        {
            return 1;
        }

        var scale = mode switch
        {
            PageFit.Screen => 1,
            PageFit.Width => Math.Max(1, viewport.Width / fitted.Width),
            PageFit.Height => Math.Max(1, viewport.Height / fitted.Height),
            // Never below fit-to-screen: a small scan at its own pixels looks like a failure to load.
            PageFit.Original => Math.Max(1, image.Width / fitted.Width),
            _ => 1,
        };
        return Math.Min(scale, Ceiling);
    }

    /// <summary>
    /// Whether a double click goes back to the fit rather than in from it. The tolerance absorbs
    /// the rounding a view's own zoom carries, which an exact comparison reads as "past fit" forever.
    /// </summary>
    public static bool IsZoomedPastFit(double current, double fit) => current > fit * 1.01;

    /// <summary>Where a double click lands: back to the fit when past it, else in by the factor and never past the ceiling.</summary>
    public static double DoubleClickTarget(double current, double fit) =>
        IsZoomedPastFit(current, fit) ? fit : Math.Min(fit * DoubleClickFactor, Ceiling);

    /// <summary>One step in. At the ceiling the scale is returned unchanged.</summary>
    public static double StepIn(double current) => Clamp(current * StepFactor);

    /// <summary>One step out. At the floor the scale is returned unchanged.</summary>
    public static double StepOut(double current) => Clamp(current / StepFactor);

    /// <summary>The wheel with the modifier held: one notch in or out per 120 units of delta, in either direction.</summary>
    public static double WheelZoom(double current, int wheelDelta)
    {
        if (wheelDelta == 0)
        {
            return current;
        }

        var notches = Math.Max(1, Math.Abs(wheelDelta) / 120);
        var scale = current;
        for (var i = 0; i < notches; i++)
        {
            scale = wheelDelta > 0 ? StepIn(scale) : StepOut(scale);
        }

        return scale;
    }

    public static double Clamp(double scale) => Math.Clamp(scale, Floor, Ceiling);

    /// <summary>
    /// The pan offset that keeps the content inside the viewport: zero slack centres the page, and
    /// a zoomed page never scrolls past its own edge.
    /// </summary>
    public static double ClampOffset(double offset, double contentLength, double viewportLength)
    {
        var slack = Math.Max(0, contentLength - viewportLength);
        return Math.Clamp(offset, 0, slack);
    }

    /// <summary>
    /// The offset after zooming about a point, so the pixel under the pointer stays under the
    /// pointer (desktop-experience: "the page zooms around the pointer").
    /// </summary>
    public static double OffsetZoomedAbout(double offset, double anchor, double oldScale, double newScale, double contentLength, double viewportLength)
    {
        if (oldScale <= 0)
        {
            return ClampOffset(offset, contentLength, viewportLength);
        }

        var ratio = newScale / oldScale;
        var zoomed = (offset + anchor) * ratio - anchor;
        return ClampOffset(zoomed, contentLength, viewportLength);
    }
}
