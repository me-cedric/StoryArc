using System.Globalization;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Animation;
using StoryArc.Interop.Library;
using StoryArc.Interop.Opening;
using StoryArc.Interop.Shell;
using StoryArc.Interop.Sources;
using StoryArc.Interop.SystemSettings;
using StoryArc.Windows.Library;
using StoryArc.Windows.Shell;
using Windows.ApplicationModel;
using Windows.System;
// System.Globalization (CultureInfo, above) also declares a SortKey class: CS0104 without this alias.
using SortKey = StoryArc.Interop.Library.SortKey;

namespace StoryArc.Windows;

/// <summary>
/// The library window: one per app, at its saved frame when the last run left one (desktop-clients
/// tasks 2.37, 2.43 and 2.47a to 2.47d). It shows Home, the library and Downloads from the host's
/// <see cref="LibraryService"/>, puts the search results in the content column while text is in the
/// title bar's field, pushes a publication's detail into the content frame, lists the folder sources
/// with their state, and takes dropped files and folders.
/// </summary>
public sealed partial class MainWindow : Window
{
    private readonly AppHost _host;
    private readonly LibraryQueryState _query = new();
    private readonly LibraryViewModel _view = new();
    private readonly SemaphoreSlim _dialog = new(1);
    private bool _isShowingDetail;
    private bool _isShowingPreferences;

    internal MainWindow(AppHost host, LibraryWindowState? restored)
    {
        _host = host;
        InitializeComponent();

        // Windows.ApplicationModel.AppInfo: the display name from Package.appxmanifest, so the window,
        // the title bar and the taskbar agree with the Start menu. The name is a brand, the same in every language.
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

        // The three destinations, named as the iOS tab bar names them; search lives in the title bar.
        HomeItem.Content = Strings.Get("tab_home", "Home");
        LibraryItem.Content = Strings.Get("tab_library", "Library");
        OnDeviceItem.Content = Strings.Get("tab_downloads", "Downloads");
        SearchBox.PlaceholderText = Strings.Get("library_search_prompt", "Search");
        AddFolderButton.Content = Strings.Get("sources_add", "Add a library");
        ToolTipService.SetToolTip(RefreshButton, Strings.Get("sources_action_refresh", "Refresh"));
        FilterButton.Content = Strings.Get("library_filter", "Filter");
        SortButton.Content = Strings.Get("library_sort", "Sort");
        GridChoice.Text = Strings.Get("library_layout_grid", "Grid");
        ListChoice.Text = Strings.Get("library_layout_list", "List");
        RefusalsBar.Title = Strings.Get("library_skipped_list", "What couldn’t be opened");

        if (_host.Library is { } library)
        {
            library.Changed += Refresh;
        }

        Activated += (sender, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated)
            {
                _host.Library?.Focused();
            }
        };
        Closed += (sender, args) =>
        {
            if (_host.Library is { } service)
            {
                service.Changed -= Refresh;
            }
        };

        // The window opens on Home (capability home-screen).
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

    /// <summary>The library's own commands from the menu or a shortcut.</summary>
    internal void Run(string commandId)
    {
        switch (commandId)
        {
            case "find":
                SearchBox.Focus(FocusState.Keyboard);
                break;
            case "viewGrid":
                LayoutBar.SelectedItem = GridChoice;
                break;
            case "viewList":
                LayoutBar.SelectedItem = ListChoice;
                break;
            case "goHome":
                Navigation.SelectedItem = HomeItem;
                break;
            case "goLibrary":
                Navigation.SelectedItem = LibraryItem;
                break;
            case "goDownloads":
                Navigation.SelectedItem = OnDeviceItem;
                break;
            case "continueReading":
                if (CoreLibrary.ContinueReading(Records()).FirstOrDefault() is { } next)
                {
                    Read(next);
                }

                break;
            case "showDetails":
                if (LibraryItems.SelectedItem is CoverCell selected)
                {
                    ShowDetail(selected.Record);
                }

                break;
        }
    }

    /// <summary>
    /// A dropped folder: the app asks whether to add it as a folder library and adds it only when the
    /// reader agrees (desktop-experience, "Dropping a folder"). One question at a time.
    /// </summary>
    internal async Task OfferFolderAsync(string path)
    {
        await _dialog.WaitAsync();
        try
        {
            var dialog = new ContentDialog
            {
                XamlRoot = Root.XamlRoot,
                Title = string.Format(CultureInfo.CurrentCulture, Strings.Get("sources_add_folder_ask___", "Add “{0}” as a library?"), Path.GetFileName(Path.TrimEndingDirectorySeparator(path))),
                Content = path,
                PrimaryButtonText = Strings.Get("sources_add", "Add a library"),
                CloseButtonText = Strings.Get("library_skipped_dismiss", "Dismiss"),
                DefaultButton = ContentDialogButton.Primary,
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                _host.Library?.AddFolder(path);
                Navigation.SelectedItem = LibraryItem;
            }
        }
        finally
        {
            _dialog.Release();
        }
    }

    /// <summary>
    /// The system's folder picker, <c>Microsoft.Windows.Storage.Pickers.FolderPicker</c> (Windows App SDK
    /// 1.8 and later), owned by this window. The chosen folder becomes a source, or takes the place of
    /// the source that needed access again.
    /// </summary>
    internal async Task PickFolderAsync(SourceStatus? sourceToReplace)
    {
        Activate();
        var picker = new Microsoft.Windows.Storage.Pickers.FolderPicker(AppWindow.Id);
        var picked = await picker.PickSingleFolderAsync();
        if (picked is null || _host.Library is not { } library)
        {
            return;
        }

        if (sourceToReplace is null)
        {
            library.AddFolder(picked.Path);
        }
        else
        {
            library.ChooseAgain(sourceToReplace.Source.Id, picked.Path);
        }

        Navigation.SelectedItem = LibraryItem;
    }

    private IReadOnlyList<LibraryRecord> Records() => _host.Library?.Records ?? [];

    /// <summary>Redraws whatever the content column shows from the host's library.</summary>
    private void Refresh()
    {
        ShowRefusals();
        ShowSources();

        // A rescan never takes the reader off the detail page or the preferences they are reading.
        if (_isShowingDetail || _isShowingPreferences)
        {
            return;
        }

        switch (_query.ContentDestination)
        {
            case LibraryDestination.Home:
                ShowHome();
                break;
            default:
                ShowLibrary();
                break;
        }
    }

    private void ShowContent(UIElement visible)
    {
        foreach (var element in new UIElement[] { HomeView, LibraryView, DetailFrame, Preferences })
        {
            element.Visibility = element == visible ? Visibility.Visible : Visibility.Collapsed;
        }

        Navigation.IsBackButtonVisible = visible == DetailFrame ? NavigationViewBackButtonVisible.Visible : NavigationViewBackButtonVisible.Collapsed;
        Navigation.IsBackEnabled = visible == DetailFrame;
        _isShowingDetail = visible == DetailFrame;
        _isShowingPreferences = visible == Preferences;
    }

    /// <summary>Home: Continue reading and Up next, each absent when empty; one sentence when both are.</summary>
    private void ShowHome()
    {
        ShowContent(HomeView);
        HomeShelvesPanel.Children.Clear();
        var shelves = HomeShelves.From(Records());
        if (shelves.IsEmpty)
        {
            HomeShelvesPanel.Children.Add(new TextBlock
            {
                Text = Strings.Get("home_nothingOpen", "Nothing open yet. Pick something from your library."),
                Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
                Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            });
            return;
        }

        foreach (var shelf in shelves.Shelves)
        {
            var heading = new TextBlock
            {
                Text = shelf.Kind == ShelfKind.ContinueReading ? Strings.Get("home_keepReading", "Continue reading") : Strings.Get("home_upNext", "Up next"),
                Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"],
            };
            var row = new ItemsView
            {
                ItemsSource = shelf.Items.Select(Cell).ToList(),
                ItemTemplate = (DataTemplate)Root.Resources["GridCellTemplate"],
                Layout = new StackLayout { Orientation = Orientation.Horizontal, Spacing = 16 },
                SelectionMode = ItemsViewSelectionMode.None,
                IsItemInvokedEnabled = true,
                Height = 340,
            };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(row, heading.Text);
            row.ItemInvoked += OnItemInvoked;
            HomeShelvesPanel.Children.Add(heading);
            HomeShelvesPanel.Children.Add(row);
        }
    }

    /// <summary>The library, Downloads or the search results: the query state's records in the chosen layout.</summary>
    private void ShowLibrary()
    {
        ShowContent(LibraryView);
        var destination = _query.ContentDestination;
        ViewTitle.Text = destination switch
        {
            LibraryDestination.Search => string.Format(CultureInfo.CurrentCulture, Strings.Get("library_search_results___", "Results for “{0}”"), _query.SearchText),
            LibraryDestination.Downloads => Strings.Get("tab_downloads", "Downloads"),
            _ => Strings.Get("tab_library", "Library"),
        };

        var records = destination == LibraryDestination.Downloads ? Records().Where(record => record.IsDownloaded) : Records();
        _view.Load(_query.Apply(records));
        LibraryItems.ItemsSource = _view.Records.Select(Cell).ToList();
        FillFilterFlyout();
        FillSortFlyout();

        LibraryEmptyText.Visibility = _view.IsEmpty ? Visibility.Visible : Visibility.Collapsed;
        LibraryEmptyText.Text = destination switch
        {
            LibraryDestination.Search => string.Format(CultureInfo.CurrentCulture, Strings.Get("library_empty_search___", "Nothing matches “{0}”."), _query.SearchText),
            _ when _query.Filters.ActiveCount > 0 => Strings.Get("library_empty_filtered", "Nothing matches the filters you set."),
            LibraryDestination.Downloads => Strings.Get("library_empty_onDevice", "Nothing in your library is on this device yet."),
            _ => Strings.Get("library_empty_subtitle", "Choose a file and start reading. You can add a whole folder whenever you like."),
        };
    }

    /// <summary>The folder sources by name; a source offline or needing access is grey, and the second offers to choose the folder again.</summary>
    private void ShowSources()
    {
        if (_host.Library is not { } library)
        {
            return;
        }

        var buttons = new List<UIElement>();
        foreach (var status in library.Sources)
        {
            var button = new Button { Content = status.Source.Name };
            var state = status.Availability switch
            {
                FolderAvailability.Offline => Strings.Get("source_state_unreachable", "Not answering"),
                FolderAvailability.NeedsAccess => Strings.Get("source_unauthorized_choose", "Choose this folder again"),
                _ => status.Source.Path,
            };
            ToolTipService.SetToolTip(button, state);
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, $"{status.Source.Name}, {state}");
            if (status.Availability != FolderAvailability.Available)
            {
                button.Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorTertiaryBrush"];
            }

            var captured = status;
            button.Click += (sender, args) =>
            {
                if (captured.Availability == FolderAvailability.NeedsAccess)
                {
                    _ = PickFolderAsync(captured);
                }
                else
                {
                    _query.Filters = _query.Filters with { SourceId = captured.Source.Id };
                    Navigation.SelectedItem = LibraryItem;
                    Refresh();
                }
            };
            var menu = new MenuFlyout();
            var remove = new MenuFlyoutItem { Text = Strings.Get("source_remove", "Remove") };
            remove.Click += (sender, args) => library.RemoveFolder(captured.Source.Id);
            menu.Items.Add(remove);
            button.ContextFlyout = menu;
            buttons.Add(button);
        }

        SourcesList.ItemsSource = buttons;
        var unwatched = library.Sources.Any(status => !status.IsWatched && status.Availability == FolderAvailability.Available);
        UnwatchedNote.Visibility = unwatched ? Visibility.Visible : Visibility.Collapsed;
        UnwatchedNote.Text = Strings.Get("library_notWatched", "Not watched live: checked every 10 seconds and when this window comes forward.");
    }

    /// <summary>What couldn't be opened, each by name with its reason.</summary>
    private void ShowRefusals()
    {
        var refusals = _host.Library?.Refusals ?? [];
        RefusalsBar.IsOpen = refusals.Count > 0;
        RefusalsBar.Message = string.Join(Environment.NewLine, refusals.Select(refusal => $"{refusal.Name}: {refusal.Reason}"));
    }

    private void ShowDetail(LibraryRecord record)
    {
        ShowContent(DetailFrame);
        var request = new DetailRequest(record, _host.Library?.IsAvailable(record) ?? true, Read);
        _ = DetailFrame.Navigate(typeof(PublicationDetailPage), request, new DrillInNavigationTransitionInfo());
    }

    private void Read(LibraryRecord record) => _host.OpenPaths([record.Id], OpenOrigin.Library);

    private CoverCell Cell(LibraryRecord record) => new(record, cell => Read(cell.Record), cell => ShowDetail(cell.Record));

    private void FillFilterFlyout()
    {
        FilterFlyout.Items.Clear();
        var filters = _query.Filters;
        FilterButton.Content = filters.ActiveCount > 0
            ? string.Format(CultureInfo.CurrentCulture, Strings.Get("library_filter_active__lld_other", "{0} filters"), filters.ActiveCount)
            : Strings.Get("library_filter", "Filter");

        AddGroup(Strings.Get("library_filter_format", "Kind of file"), "format",
            Enum.GetValues<PublicationFormat>().Select(format => (format.ToString().ToUpperInvariant(), (object?)format)),
            filters.Format, value => _query.Filters = _query.Filters with { Format = (PublicationFormat?)value });
        AddGroup(Strings.Get("library_filter_readState", "Read or unread"), "read",
            new[]
            {
                (Strings.Get("library_readState_unread", "Unread"), (object?)ReadingState.Unread),
                (Strings.Get("library_readState_inProgress", "In progress"), ReadingState.InProgress),
                (Strings.Get("library_readState_finished", "Finished"), ReadingState.Finished),
            },
            filters.ReadingState, value => _query.Filters = _query.Filters with { ReadingState = (ReadingState?)value });
        AddGroup(Strings.Get("library_filter_download", "Downloaded or not"), "download",
            new[]
            {
                (Strings.Get("library_filter_download_yes", "Downloaded"), (object?)true),
                (Strings.Get("library_filter_download_no", "Not downloaded"), false),
            },
            filters.IsDownloaded, value => _query.Filters = _query.Filters with { IsDownloaded = (bool?)value });
        AddGroup(Strings.Get("library_filter_library", "Which library"), "source",
            (_host.Library?.Sources ?? []).Select(status => (status.Source.Name, (object?)status.Source.Id)),
            filters.SourceId, value => _query.Filters = _query.Filters with { SourceId = (string?)value });

        FilterFlyout.Items.Add(new MenuFlyoutSeparator());
        var clear = new MenuFlyoutItem { Text = Strings.Get("library_filter_clear", "Clear filters"), IsEnabled = filters.ActiveCount > 0 };
        clear.Click += (sender, args) =>
        {
            _query.Filters = LibraryFilters.None;
            Refresh();
        };
        FilterFlyout.Items.Add(clear);
    }

    private void AddGroup(string title, string group, IEnumerable<(string Label, object? Value)> choices, object? current, Action<object?> choose)
    {
        var sub = new MenuFlyoutSubItem { Text = title };
        foreach (var (label, value) in choices.Prepend((Strings.Get("library_filter_decade_any", "Any"), null)))
        {
            var item = new RadioMenuFlyoutItem { Text = label, GroupName = group, IsChecked = Equals(value, current) };
            item.Click += (sender, args) =>
            {
                choose(value);
                Refresh();
            };
            sub.Items.Add(item);
        }

        FilterFlyout.Items.Add(sub);
    }

    private void FillSortFlyout()
    {
        SortFlyout.Items.Clear();
        var keys = new (SortKey Key, string StringKey, string Fallback)[]
        {
            (SortKey.Title, "library_sort_title", "Title"),
            (SortKey.Series, "library_sort_series", "Series"),
            (SortKey.DateAdded, "library_sort_dateAdded", "Date added"),
            (SortKey.LastRead, "library_sort_lastRead", "Last read"),
            (SortKey.Progress, "library_sort_progress", "Progress"),
            (SortKey.Year, "library_sort_year", "Year"),
            (SortKey.FileSize, "library_sort_fileSize", "File size"),
        };
        foreach (var (key, stringKey, fallback) in keys)
        {
            var item = new RadioMenuFlyoutItem { Text = Strings.Get(stringKey, fallback), GroupName = "sort", IsChecked = _query.Sort == key };
            item.Click += (sender, args) =>
            {
                _query.Sort = key;
                Refresh();
            };
            SortFlyout.Items.Add(item);
        }

        SortFlyout.Items.Add(new MenuFlyoutSeparator());
        foreach (var (descending, stringKey, fallback) in new[] { (false, "library_sort_ascending", "Ascending"), (true, "library_sort_descending", "Descending") })
        {
            var item = new RadioMenuFlyoutItem { Text = Strings.Get(stringKey, fallback), GroupName = "direction", IsChecked = _query.SortDescending == descending };
            item.Click += (sender, args) =>
            {
                _query.SortDescending = descending;
                Refresh();
            };
            SortFlyout.Items.Add(item);
        }
    }

    private void OnSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ShowContent(Preferences);
            return;
        }

        // SelectedItem is an object; the menu items are NavigationViewItem, which declares its own ==.
        // Cast first, as CS0252 asks, so the comparison is the item's own and not an object reference.
        var selected = args.SelectedItem as NavigationViewItem;
        var destination = selected == LibraryItem ? LibraryDestination.Library
            : selected == OnDeviceItem ? LibraryDestination.Downloads
            : LibraryDestination.Home;
        _isShowingDetail = false;
        _isShowingPreferences = false;
        _query.Navigate(destination);
        SearchBox.Text = string.Empty;
        Refresh();
    }

    private void OnBackRequested(NavigationView sender, NavigationViewBackRequestedEventArgs args)
    {
        if (_isShowingDetail)
        {
            _isShowingDetail = false;
            Refresh();
        }
    }

    /// <summary>Text in the field: the results take over the content column; the field itself never moves.</summary>
    private void OnSearchTextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason != AutoSuggestionBoxTextChangeReason.UserInput)
        {
            return;
        }

        _query.SetSearchText(sender.Text);
        _isShowingDetail = false;
        _isShowingPreferences = false;
        Refresh();
    }

    private void OnSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        _query.SetSearchText(args.QueryText);
        _isShowingDetail = false;
        _isShowingPreferences = false;
        Refresh();
    }

    /// <summary>Escape in the field clears it and the column returns to where the reader came from.</summary>
    private void OnSearchKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape && _query.IsShowingResults)
        {
            SearchBox.Text = string.Empty;
            _query.ClearSearch();
            Refresh();
            args.Handled = true;
        }
    }

    private void OnLayoutChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        var isList = sender.SelectedItem == ListChoice;
        _view.Presentation = isList ? LibraryPresentation.List : LibraryPresentation.Grid;
        LibraryItems.ItemTemplate = (DataTemplate)Root.Resources[isList ? "ListRowTemplate" : "GridCellTemplate"];
        LibraryItems.Layout = (Microsoft.UI.Xaml.Controls.Layout)Root.Resources[isList ? "ListLayout" : "GridLayout"];
    }

    /// <summary>Invoking a cell (double click, Enter) opens the publication in its reader window.</summary>
    private void OnItemInvoked(ItemsView sender, ItemsViewItemInvokedEventArgs args)
    {
        if (args.InvokedItem is CoverCell cell)
        {
            Read(cell.Record);
        }
    }

    private void OnAddFolder(object sender, RoutedEventArgs args) => _ = PickFolderAsync(sourceToReplace: null);

    private void OnRefresh(object sender, RoutedEventArgs args) => _host.Library?.RefreshAll();

    private void OnRefusalsClosed(InfoBar sender, InfoBarClosedEventArgs args) => _host.Library?.DismissRefusals();

    private void OnDragOver(object sender, DragEventArgs args) => Drops.Accept(args);

    private async void OnDrop(object sender, DragEventArgs args) =>
        _host.OpenPaths(await Drops.PathsAsync(args), OpenOrigin.Drop);

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
