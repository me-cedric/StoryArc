namespace StoryArc.Interop.SystemSettings;

/// <summary>
/// What the system says about appearance, effects, contrast, motion and text size, read on
/// Windows from <c>Windows.UI.ViewManagement.UISettings</c> (<c>AdvancedEffectsEnabled</c>,
/// <c>AnimationsEnabled</c>, <c>TextScaleFactor</c>, <c>GetColorValue</c>) and
/// <c>AccessibilitySettings.HighContrast</c>. A record so the readings test on any host.
/// </summary>
public readonly record struct SystemSettingsSnapshot(
    bool IsDarkAppearance,
    bool AnimationsEnabled,
    bool TransparencyEffectsEnabled,
    bool HighContrast,
    double TextScaleFactor)
{
    /// <summary>A system with every setting at its default.</summary>
    public static SystemSettingsSnapshot Default { get; } = new(false, true, true, false, 1.0);
}

public enum ChromeMaterial
{
    /// <summary>Mica behind the title bar and the pane, in-app acrylic over the page.</summary>
    Translucent,

    /// <summary>The same chrome drawn opaque, with the overlay token as the fill.</summary>
    Opaque,
}

public enum MotionPolicy
{
    Full,

    /// <summary>No sliding or curling: a fast fade, and the curl is off.</summary>
    FastFade,
}

public enum LibraryPresentation
{
    Grid,
    List,
}

/// <summary>
/// The readings of desktop-experience "Transparency off", "Text size, contrast and motion follow
/// the system" and "The system switches appearance" (desktop-clients task 2.45).
/// </summary>
public static class SystemAppearance
{
    /// <summary>
    /// The Windows text scale at which the library becomes a list (docs/designs/desktop/windows.md,
    /// section 10): the largest value the Settings slider offers is 225 percent.
    /// </summary>
    public const double LargestTextScale = 2.25;

    /// <summary>Opaque when transparency effects are off or contrast is increased; translucent otherwise.</summary>
    public static ChromeMaterial Material(SystemSettingsSnapshot settings) =>
        settings.TransparencyEffectsEnabled && !settings.HighContrast ? ChromeMaterial.Translucent : ChromeMaterial.Opaque;

    /// <summary>A fast fade when the system asks for reduced motion.</summary>
    public static MotionPolicy Motion(SystemSettingsSnapshot settings) =>
        settings.AnimationsEnabled ? MotionPolicy.Full : MotionPolicy.FastFade;

    /// <summary>At the largest text size the library is a list, so no label is cut.</summary>
    public static LibraryPresentation Library(SystemSettingsSnapshot settings, LibraryPresentation chosen) =>
        settings.TextScaleFactor >= LargestTextScale ? LibraryPresentation.List : chosen;

    /// <summary>
    /// The transition mode the reader shows, from the one it asked for: the curl is wave 5 and
    /// absent on this build, so it shows as the nearest available mode; reduced motion gives the
    /// fast fade. The settings say why in grey (desktop-experience, "The curl where it is not available").
    /// </summary>
    public static TransitionMode EffectiveTransition(TransitionMode requested, SystemSettingsSnapshot settings, bool isCurlAvailable)
    {
        if (Motion(settings) == MotionPolicy.FastFade)
        {
            return TransitionMode.Fade;
        }

        return requested == TransitionMode.Curl && !isCurlAvailable ? TransitionMode.Slide : requested;
    }
}

public enum TransitionMode
{
    Slide,
    Fade,
    Curl,
    Scroll,
}
