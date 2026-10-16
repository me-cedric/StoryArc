namespace StoryArc.Interop.Settings;

/// <summary>The theme the chrome asks WinUI for. System leaves <c>RequestedTheme</c> at Default, so the app follows Windows.</summary>
public enum ThemeKind
{
    System,
    Light,
    Dark,
}

/// <summary>
/// What each Appearance choice does to the chrome today. OLED Dark and Natural are further token
/// dictionaries that are not drawn yet (docs/designs/desktop/windows.md, section 11): until they
/// are, OLED Dark takes the dark theme and Natural follows the system, and the page says in grey
/// that the choice is saved and not yet drawn.
/// </summary>
public static class AppearanceTheme
{
    public static ThemeKind For(AppearanceChoice choice) => choice switch
    {
        AppearanceChoice.Light => ThemeKind.Light,
        AppearanceChoice.Dark or AppearanceChoice.OledDark => ThemeKind.Dark,
        _ => ThemeKind.System,
    };

    public static bool IsPending(AppearanceChoice choice) => choice is AppearanceChoice.OledDark or AppearanceChoice.Natural;
}

/// <summary>
/// The settings in memory, read once at start and saved on every change (desktop-clients tasks
/// 2.47 and 2.47e). The file is read and written through delegates so the store tests on any host.
/// A write that fails keeps the choice for this run and never throws at the page.
/// </summary>
public sealed class SettingsStore
{
    private readonly Action<string> _write;

    public SettingsStore(Func<string?> read, Action<string> write)
    {
        _write = write;
        Current = AppSettings.Restore(read());
    }

    public AppSettings Current { get; private set; }

    /// <summary>Raised with the new settings after a change that altered them.</summary>
    public event Action<AppSettings>? Changed;

    public void Update(Func<AppSettings, AppSettings> change)
    {
        var next = change(Current);
        if (next == Current)
        {
            return;
        }

        Current = next;
        try
        {
            _write(next.Save());
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }

        Changed?.Invoke(next);
    }
}
