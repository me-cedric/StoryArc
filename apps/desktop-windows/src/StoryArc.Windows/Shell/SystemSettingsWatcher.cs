using Microsoft.UI.Dispatching;
using StoryArc.Interop.Settings;
using StoryArc.Interop.SystemSettings;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace StoryArc.Windows.Shell;

/// <summary>
/// Reads the system settings the app follows and says when they change (desktop-clients tasks
/// 2.45 and 2.47e). <c>Windows.UI.ViewManagement.UISettings</c> gives <c>AnimationsEnabled</c>
/// (reduced motion), <c>AdvancedEffectsEnabled</c> (transparency effects), <c>TextScaleFactor</c>
/// and <c>GetColorValue(UIColorType)</c> for the accent and its six shades, with the events
/// <c>ColorValuesChanged</c>, <c>AnimationsEnabledChanged</c>, <c>AdvancedEffectsEnabledChanged</c>
/// and <c>TextScaleFactorChanged</c>; <c>AccessibilitySettings.HighContrast</c> and
/// <c>HighContrastChanged</c> give contrast. The events arrive off the UI thread, so each is
/// forwarded through the window's <c>DispatcherQueue</c>.
/// </summary>
internal sealed class SystemSettingsWatcher
{
    private readonly UISettings _ui = new();
    private readonly AccessibilitySettings _accessibility = new();
    private readonly DispatcherQueue _dispatcher;

    public SystemSettingsWatcher(DispatcherQueue dispatcher)
    {
        _dispatcher = dispatcher;
        Current = Read();
        _ui.ColorValuesChanged += (sender, args) => Forward();
        _ui.AnimationsEnabledChanged += (sender, args) => Forward();
        _ui.AdvancedEffectsEnabledChanged += (sender, args) => Forward();
        _ui.TextScaleFactorChanged += (sender, args) => Forward();
        _accessibility.HighContrastChanged += (sender, args) => Forward();
    }

    /// <summary>Raised on the UI thread with the new readings.</summary>
    public event Action<SystemSettingsSnapshot>? Changed;

    public SystemSettingsSnapshot Current { get; private set; }

    /// <summary>The system accent and its shades. Windows always offers one; the choice is hidden only where it does not.</summary>
    public AccentPalette? SystemAccent()
    {
        try
        {
            return new AccentPalette(
                ToArgb(_ui.GetColorValue(UIColorType.Accent)),
                ToArgb(_ui.GetColorValue(UIColorType.AccentLight1)),
                ToArgb(_ui.GetColorValue(UIColorType.AccentLight2)),
                ToArgb(_ui.GetColorValue(UIColorType.AccentLight3)),
                ToArgb(_ui.GetColorValue(UIColorType.AccentDark1)),
                ToArgb(_ui.GetColorValue(UIColorType.AccentDark2)),
                ToArgb(_ui.GetColorValue(UIColorType.AccentDark3)));
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }

    private SystemSettingsSnapshot Read()
    {
        // The system appearance: a dark background colour means the dark theme.
        var background = _ui.GetColorValue(UIColorType.Background);
        var isDark = background.R + background.G + background.B < 3 * 128;
        return new SystemSettingsSnapshot(
            isDark,
            _ui.AnimationsEnabled,
            _ui.AdvancedEffectsEnabled,
            _accessibility.HighContrast,
            _ui.TextScaleFactor);
    }

    private void Forward() =>
        _dispatcher.TryEnqueue(() =>
        {
            Current = Read();
            Changed?.Invoke(Current);
        });

    public static Argb ToArgb(Color colour) => new(colour.A, colour.R, colour.G, colour.B);

    public static Color ToColor(Argb colour) => Color.FromArgb(colour.A, colour.R, colour.G, colour.B);
}
