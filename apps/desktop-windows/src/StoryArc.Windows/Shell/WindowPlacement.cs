using System.Globalization;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using StoryArc.Interop.Shell;
using Windows.Graphics;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The bridge between the pure window state and <c>Microsoft.UI.Windowing.AppWindow</c>
/// (desktop-clients task 2.37). <c>AppWindow.Position</c>, <c>Size</c>, <c>Move</c>,
/// <c>Resize</c> and <c>MoveAndResize(RectInt32)</c> are in physical pixels of the screen, which
/// is the unit the saved frame keeps. <c>DisplayArea.FindAll()</c> lists the displays connected
/// now with <c>OuterBounds</c> and <c>DisplayId</c>; <c>GetFromWindowId</c> names the one a
/// window is on. <c>OverlappedPresenter.State</c> says whether the window is maximized.
/// </summary>
internal static class WindowPlacement
{
    public static WindowFrame FrameOf(AppWindow window) =>
        new(window.Position.X, window.Position.Y, window.Size.Width, window.Size.Height);

    public static string? DisplayIdOf(AppWindow window)
    {
        var area = DisplayArea.GetFromWindowId(window.Id, DisplayAreaFallback.Nearest);
        return area?.DisplayId.Value.ToString(CultureInfo.InvariantCulture);
    }

    public static IReadOnlyList<DisplayBounds> Displays() =>
        DisplayArea.FindAll()
            .Select(area => new DisplayBounds(
                area.DisplayId.Value.ToString(CultureInfo.InvariantCulture),
                area.OuterBounds.X,
                area.OuterBounds.Y,
                area.OuterBounds.Width,
                area.OuterBounds.Height))
            .ToList();

    public static bool IsMaximized(AppWindow window) =>
        window.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Maximized };

    /// <summary>The monitor scale of the window: 1 at 100 percent, 2 at 200 percent.</summary>
    public static double Scale(AppWindow window) =>
        Win32.GetDpiForWindow(Win32Interop.GetWindowFromWindowId(window.Id)) / 96.0;

    /// <summary>Puts the window at a saved frame, fitted to the displays connected now, and maximizes it when it was.</summary>
    public static void Restore(AppWindow window, WindowFrame frame, string? displayId, bool isMaximized)
    {
        var scale = Scale(window);
        var fitted = frame.FitTo(Displays(), displayId, Pixels(WindowDefaults.MinWidth, scale), Pixels(WindowDefaults.MinHeight, scale));
        window.MoveAndResize(new RectInt32(fitted.X, fitted.Y, fitted.Width, fitted.Height));
        if (isMaximized && window.Presenter is OverlappedPresenter presenter)
        {
            presenter.Maximize();
        }
    }

    /// <summary>Sizes a window that was never saved and centres it on its display's work area.</summary>
    public static void OpenAtDefault(AppWindow window, int widthDip, int heightDip)
    {
        var scale = Scale(window);
        var width = Pixels(widthDip, scale);
        var height = Pixels(heightDip, scale);
        var area = DisplayArea.GetFromWindowId(window.Id, DisplayAreaFallback.Nearest);
        if (area is null)
        {
            window.Resize(new SizeInt32(width, height));
            return;
        }

        var work = area.WorkArea;
        width = Math.Min(width, work.Width);
        height = Math.Min(height, work.Height);
        var x = work.X + (work.Width - width) / 2;
        var y = work.Y + (work.Height - height) / 2;
        window.MoveAndResize(new RectInt32(x, y, width, height));
    }

    /// <summary>The smallest size the window accepts (Windows App SDK 1.7 and later, <c>OverlappedPresenter.PreferredMinimumWidth</c>).</summary>
    public static void SetMinimumSize(AppWindow window)
    {
        if (window.Presenter is OverlappedPresenter presenter)
        {
            var scale = Scale(window);
            presenter.PreferredMinimumWidth = Pixels(WindowDefaults.MinWidth, scale);
            presenter.PreferredMinimumHeight = Pixels(WindowDefaults.MinHeight, scale);
        }
    }

    private static int Pixels(int dip, double scale) => (int)Math.Round(dip * scale);
}
