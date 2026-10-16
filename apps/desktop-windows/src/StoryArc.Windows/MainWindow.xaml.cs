using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.ApplicationModel.Resources;
using StoryArc.Interop;
using StoryArc.Interop.Shell;
using StoryArc.Windows.Shell;
using Windows.ApplicationModel;

namespace StoryArc.Windows;

/// <summary>The library window: one per app, at its saved frame when the last run left one.</summary>
public sealed partial class MainWindow : Window
{
    private readonly AppHost _host;

    /// <summary>
    /// The app's strings, generated from the iOS catalogues into <c>Strings/&lt;lang&gt;/Resources.resw</c>
    /// (<c>pnpm strings:desktop</c>). Microsoft.Windows.ApplicationModel.Resources.ResourceLoader reads
    /// the language the user set, and falls back to English.
    /// </summary>
    private readonly ResourceLoader _strings = new();

    internal MainWindow(AppHost host, LibraryWindowState? restored)
    {
        _host = host;
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

        if (restored is not null)
        {
            WindowPlacement.Restore(AppWindow, restored.Frame, restored.DisplayId, restored.IsMaximized);
        }
        else
        {
            WindowPlacement.OpenAtDefault(AppWindow, WindowDefaults.LibraryWidth, WindowDefaults.LibraryHeight);
        }

        WindowPlacement.SetMinimumSize(AppWindow);

        Func<string, bool> isAvailable = id => CommandRouting.IsHandled(id, WindowKind.Library);
        Action<string> invoke = id => _host.Invoke(id, this);
        Menu.Initialize(WindowKind.Library, isAvailable, invoke);
        MenuBuilder.AttachAccelerators(Root, WindowKind.Library, isAvailable, invoke);
        Preferences.Initialize(_host);

        // The four destinations, named as the iOS tab bar names them (LibraryDestination: home,
        // library, onDevice, search). The list does not change when sources are added or removed.
        HomeItem.Content = _strings.GetString("tab_home");
        LibraryItem.Content = _strings.GetString("tab_library");
        OnDeviceItem.Content = _strings.GetString("tab_downloads");
        SearchItem.Content = _strings.GetString("tab_search");

        CoreVersionText.Text = ReadCoreVersion();
        Navigation.SelectedItem = HomeItem;

        AppWindow.Changed += OnAppWindowChanged;
        _host.LibraryMoved(Snapshot());
    }

    /// <summary>Selects the Settings item of the pane, which shows the preferences page.</summary>
    internal void ShowPreferences()
    {
        Navigation.SelectedItem = Navigation.SettingsItem;
        Activate();
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
        Preferences.Visibility = args.IsSettingsSelected ? Visibility.Visible : Visibility.Collapsed;
        EmptyState.Visibility = args.IsSettingsSelected ? Visibility.Collapsed : Visibility.Visible;
        if (args.IsSettingsSelected)
        {
            return;
        }

        var item = args.SelectedItemContainer;
        SectionTitle.Text = item?.Content as string ?? string.Empty;
        EmptyText.Text = item?.Tag is string emptyKey ? _strings.GetString(emptyKey) : string.Empty;
    }

    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (args.DidPositionChange || args.DidSizeChange)
        {
            _host.LibraryMoved(Snapshot());
        }
    }

    private LibraryWindowState Snapshot() => new(
        WindowPlacement.FrameOf(AppWindow),
        WindowPlacement.IsMaximized(AppWindow),
        WindowPlacement.DisplayIdOf(AppWindow));
}
