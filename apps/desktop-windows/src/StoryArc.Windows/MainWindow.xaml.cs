using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.ApplicationModel.Resources;
using StoryArc.Interop;
using Windows.ApplicationModel;
using Windows.Graphics;

namespace StoryArc.Windows;

public sealed partial class MainWindow : Window
{
    private const double WidthDip = 1100;
    private const double HeightDip = 720;
    private const double MinWidthDip = 480;
    private const double MinHeightDip = 360;

    /// <summary>
    /// The app's strings, generated from the iOS catalogues into <c>Strings/&lt;lang&gt;/Resources.resw</c>
    /// (<c>pnpm strings:desktop</c>). Microsoft.Windows.ApplicationModel.Resources.ResourceLoader reads
    /// the language the user set, and falls back to English.
    /// </summary>
    private readonly ResourceLoader _strings = new();

    [LibraryImport("user32.dll")]
    private static partial uint GetDpiForWindow(nint hwnd);

    public MainWindow()
    {
        InitializeComponent();

        // Windows.ApplicationModel.AppInfo: the display name from Package.appxmanifest, so the window,
        // the title bar and the taskbar agree with the Start menu. The string resources carry no app
        // name of their own; the name is a brand, the same in every language.
        var displayName = AppInfo.Current.DisplayInfo.DisplayName;
        Title = displayName;
        AppTitleBar.Title = displayName;

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

        // The four destinations, named as the iOS tab bar names them (LibraryDestination: home,
        // library, onDevice, search). The list does not change when sources are added or removed.
        HomeItem.Content = _strings.GetString("tab_home");
        LibraryItem.Content = _strings.GetString("tab_library");
        OnDeviceItem.Content = _strings.GetString("tab_downloads");
        SearchItem.Content = _strings.GetString("tab_search");

        CoreVersionText.Text = ReadCoreVersion();
        Navigation.SelectedItem = HomeItem;
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
        if (args.IsSettingsSelected)
        {
            SectionTitle.Text = _strings.GetString("home_settings");
            EmptyText.Text = string.Empty;
            return;
        }

        var item = args.SelectedItemContainer;
        SectionTitle.Text = item?.Content as string ?? string.Empty;
        EmptyText.Text = item?.Tag is string emptyKey ? _strings.GetString(emptyKey) : string.Empty;
    }
}
