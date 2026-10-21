using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using StoryArc.Interop.Settings;

namespace StoryArc.Windows.Shell;

/// <summary>
/// Paints the chrome with an accent palette at run time (desktop-clients task 2.47e). App.xaml
/// aliases <c>SystemAccentColor</c> and its six shades to the brand token; this replaces those
/// seven entries in <c>Application.Current.Resources</c> with the palette's colours, which is what
/// WinUI's accent brushes read (<c>AccentFillColorDefaultBrush</c> and the rest, in
/// Common_themeresources_any.xaml). A brush that was already resolved keeps its old colour, so
/// every open window's root is asked to resolve its theme again.
/// </summary>
internal static class AccentApplier
{
    public static void Apply(AccentPalette palette, IEnumerable<Window> windows, bool retry = true)
    {
        var resources = Application.Current.Resources;
        try
        {
            resources["SystemAccentColor"] = SystemSettingsWatcher.ToColor(palette.Base);
            resources["SystemAccentColorLight1"] = SystemSettingsWatcher.ToColor(palette.Light1);
            resources["SystemAccentColorLight2"] = SystemSettingsWatcher.ToColor(palette.Light2);
            resources["SystemAccentColorLight3"] = SystemSettingsWatcher.ToColor(palette.Light3);
            resources["SystemAccentColorDark1"] = SystemSettingsWatcher.ToColor(palette.Dark1);
            resources["SystemAccentColorDark2"] = SystemSettingsWatcher.ToColor(palette.Dark2);
            resources["SystemAccentColorDark3"] = SystemSettingsWatcher.ToColor(palette.Dark3);
        }
        catch (COMException)
        {
            // At start-up the write can fail with 0x800F0902 while XAML still resolves the first window, which crashed the
            // app on CI (2026-10-21). Try once more after the current work; if that fails too, the App.xaml brand accent stays.
            if (retry)
            {
                var open = windows.ToList();
                DispatcherQueue.GetForCurrentThread()?.TryEnqueue(DispatcherQueuePriority.Low, () => Apply(palette, open, retry: false));
            }

            return;
        }

        foreach (var window in windows)
        {
            RefreshTheme(window);
        }
    }

    /// <summary>
    /// Makes every <c>ThemeResource</c> in the window resolve again by setting the root's
    /// <c>RequestedTheme</c> to the other theme and back. The pattern is Inferred, not on
    /// Microsoft Learn: WinUI re-resolves theme resources on a theme change and offers no call that
    /// does only that. The walk of task 2.47e is what proves it.
    /// </summary>
    public static void RefreshTheme(Window window)
    {
        if (window.Content is not FrameworkElement root)
        {
            return;
        }

        var wanted = root.RequestedTheme;
        root.RequestedTheme = root.ActualTheme == ElementTheme.Dark ? ElementTheme.Light : ElementTheme.Dark;
        root.RequestedTheme = wanted;
    }
}
