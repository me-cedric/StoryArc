using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop;
using Windows.Graphics;

namespace StoryArc.Windows;

public sealed partial class MainWindow : Window
{
    private const double WidthDip = 1100;
    private const double HeightDip = 720;
    private const double MinWidthDip = 480;
    private const double MinHeightDip = 360;

    [LibraryImport("user32.dll")]
    private static partial uint GetDpiForWindow(nint hwnd);

    public MainWindow()
    {
        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");

        var scale = GetDpiForWindow(Win32Interop.GetWindowFromWindowId(AppWindow.Id)) / 96.0;
        AppWindow.Resize(new SizeInt32((int)(WidthDip * scale), (int)(HeightDip * scale)));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = (int)(MinWidthDip * scale);
            presenter.PreferredMinimumHeight = (int)(MinHeightDip * scale);
        }

        CoreVersionText.Text = ReadCoreVersion();
        Navigation.SelectedItem = Navigation.MenuItems[0];
    }

    private static string ReadCoreVersion()
    {
        try
        {
            return $"Core {NativeCore.Version()}";
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return $"Core library not found: {error.Message}";
        }
    }

    private void OnSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        SectionTitle.Text = args.IsSettingsSelected
            ? "Settings"
            : (args.SelectedItemContainer?.Tag as string ?? string.Empty);
    }
}
