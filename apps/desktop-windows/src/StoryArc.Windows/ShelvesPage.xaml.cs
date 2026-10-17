using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop.Data;
using StoryArc.Interop.Library;
using StoryArc.Interop.Opening;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The shelves page (desktop-clients task 3.23a, over the core's shelves of task 3.7): a list of every collection and reading list, and one
/// shelf's page. The rules that change a shelf run in the core; what the page shows of the result is <see cref="ShelfPageModel"/>, which the model
/// tests pin: a collection by title, a list in the reader's order with how far through it the reader is, a member that is gone in grey, and an
/// addition waiting for a server after the server's own rows. Pinning puts a shelf on Home.
/// </summary>
public sealed partial class ShelvesPage : UserControl
{
    private AppHost? _host;
    private string? _shelfId;

    public ShelvesPage()
    {
        InitializeComponent();
    }

    private NetworkServices? Network => _host?.Network;

    internal void Initialize(AppHost host)
    {
        _host = host;
        NewCollectionButton.Content = Strings.Get("shelves_new_collection");
        NewListButton.Content = Strings.Get("shelves_new_list");
        if (Network is { } network)
        {
            network.Changed += Rebuild;
        }

        if (host.Library is { } library)
        {
            library.Changed += Rebuild;
        }

        Rebuild();
    }

    /// <summary>Shows the list of every shelf, or one shelf's page when <paramref name="shelfId"/> names one.</summary>
    internal void Show(string? shelfId)
    {
        _shelfId = shelfId;
        Rebuild();
    }

    private void Rebuild()
    {
        Rows.Children.Clear();
        if (Network is not { } network)
        {
            return;
        }

        if (_shelfId is { } id && network.Shelves.Find(id) is { } shelf)
        {
            ShowShelf(network, shelf);
            return;
        }

        _shelfId = null;
        ShowAll(network);
    }

    private void ShowAll(NetworkServices network)
    {
        BackButton.Visibility = Visibility.Collapsed;
        Toolbar.Visibility = Visibility.Visible;
        PageTitle.Text = Strings.Get("shelves_title");
        Subtitle.Text = network.Shelves.All.Any() ? string.Empty : Strings.Get("desktop_w3_shelves_none");
        foreach (var shelf in network.Pinned.Ordering(network.Shelves.All))
        {
            Rows.Children.Add(ShelfRow(network, shelf));
        }
    }

    private Border ShelfRow(NetworkServices network, Shelf shelf)
    {
        var pinned = network.Pinned.IsPinned(shelf);
        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(new TextBlock { Text = shelf.Name, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
        text.Children.Add(Grey(
            Strings.Get(shelf.Kind == ShelfType.Collection ? "shelves_collections" : "shelves_lists")
            + " · " + shelf.Members.Count.ToString(CultureInfo.CurrentCulture)
            + (pinned ? " · " + Strings.Get("home_pinned") : string.Empty)));

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        actions.Children.Add(MakeButton(Strings.Get("desktop_w3_shelves_openShelf"), () => Show(shelf.Id)));
        actions.Children.Add(MakeButton(
            Strings.Get(pinned ? "shelves_unpin" : "shelves_pin"),
            () => network.SetPinned(pinned ? network.Pinned.Unpinning(shelf) : network.Pinned.Pinning(shelf))));
        actions.Children.Add(MakeButton(Strings.Get("shelves_rename"), () => _ = RenameAsync(network, shelf)));
        actions.Children.Add(MakeButton(Strings.Get("shelves_delete"), () => _ = DeleteAsync(network, shelf)));
        return Card(text, actions);
    }

    private void ShowShelf(NetworkServices network, Shelf shelf)
    {
        BackButton.Visibility = Visibility.Visible;
        Toolbar.Visibility = Visibility.Collapsed;
        PageTitle.Text = shelf.Name;
        var records = _host?.Library?.Records ?? [];
        var page = ShelfPageModel.From(shelf, records, network.Edits.Edits.Where(edit => edit.Shelf.SourceId == shelf.ServerSourceId).ToList());
        Subtitle.Text = page.Rows.Count == 0
            ? Strings.Get(shelf.Kind == ShelfType.Collection ? "shelves_collection_empty" : "shelves_list_empty")
            : page.Progress is { } progress
                ? string.Format(CultureInfo.CurrentCulture, Strings.Get("shelves_list_progress__lld__lld"), progress.Finished, progress.Reported)
                : string.Empty;

        for (var index = 0; index < page.Rows.Count; index++)
        {
            Rows.Children.Add(MemberRow(network, shelf, page.Rows[index], index, page.Rows.Count));
        }
    }

    private Border MemberRow(NetworkServices network, Shelf shelf, ShelfPageRow row, int index, int count)
    {
        var text = new StackPanel { Spacing = 2 };
        var title = new TextBlock { Text = row.Title, TextTrimming = TextTrimming.CharacterEllipsis };
        if (!row.IsAvailable)
        {
            title.Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorTertiaryBrush"];
        }

        text.Children.Add(title);
        if (row.IsPending)
        {
            text.Children.Add(Grey(Strings.Get("shelves_pending_entry")));
        }
        else if (!row.IsAvailable)
        {
            text.Children.Add(Grey(Strings.Get(row.Record is null ? "shelves_list_unavailable" : "desktop_w3_shelves_notHere")));
        }

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        if (row.IsAvailable && row.Record is { } record)
        {
            actions.Children.Add(MakeButton(Strings.Get("desktop_w3_shelves_openShelf"), () => _host?.OpenPaths([record.Id], OpenOrigin.Library)));
        }

        if (!row.IsPending)
        {
            var id = row.Id;
            if (shelf.Kind == ShelfType.ReadingList)
            {
                var up = MakeButton("↑", () => network.ApplyShelves(ShelfOp.MoveEntry(shelf.Id, id, index - 1)));
                up.IsEnabled = index > 0;
                var down = MakeButton("↓", () => network.ApplyShelves(ShelfOp.MoveEntry(shelf.Id, id, index + 2)));
                down.IsEnabled = index < count - 1;
                actions.Children.Add(up);
                actions.Children.Add(down);
            }

            if (row.IsAvailable)
            {
                actions.Children.Add(MakeButton(
                    Strings.Get("desktop_w3_shelves_setCover"),
                    () => network.ApplyShelves(shelf.Kind == ShelfType.Collection ? ShelfOp.SetCollectionCover(shelf.Id, id) : ShelfOp.SetListCover(shelf.Id, id))));
            }

            actions.Children.Add(MakeButton(
                Strings.Get("library_action_removeFromShelf"),
                () => network.ApplyShelves([.. ShelfMembership.Removing(shelf, [id])])));
        }

        return Card(text, actions);
    }

    private static Border Card(UIElement text, UIElement actions)
    {
        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(text);
        Grid.SetColumn((FrameworkElement)actions, 1);
        grid.Children.Add(actions);
        return new Border
        {
            Child = grid,
            Padding = new Thickness(16, 10, 16, 10),
            BorderThickness = new Thickness(1),
            CornerRadius = (CornerRadius)Application.Current.Resources["ControlCornerRadius"],
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        };
    }

    private static TextBlock Grey(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
        Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorTertiaryBrush"],
    };

    private static Button MakeButton(string label, Action click)
    {
        var button = new Button { Content = label };
        button.Click += (sender, args) => click();
        return button;
    }

    private void OnBack(object sender, RoutedEventArgs args) => Show(null);

    private void OnNewCollection(object sender, RoutedEventArgs args) => _ = CreateAsync(ShelfType.Collection);

    private void OnNewList(object sender, RoutedEventArgs args) => _ = CreateAsync(ShelfType.ReadingList);

    private async Task CreateAsync(ShelfType kind)
    {
        if (Network is not { } network)
        {
            return;
        }

        var name = await AskNameAsync(
            Strings.Get(kind == ShelfType.Collection ? "shelves_new_collection" : "shelves_new_list"),
            Strings.Get(kind == ShelfType.Collection ? "desktop_w3_shelves_newCollectionName" : "desktop_w3_shelves_newListName"),
            Strings.Get("shelves_create"));
        if (!string.IsNullOrWhiteSpace(name))
        {
            network.ApplyShelves(kind == ShelfType.Collection ? ShelfOp.CreateCollection(name.Trim()) : ShelfOp.CreateList(name.Trim()));
        }
    }

    private async Task RenameAsync(NetworkServices network, Shelf shelf)
    {
        var name = await AskNameAsync(Strings.Get("shelves_rename"), shelf.Name, Strings.Get("shelves_rename"));
        if (!string.IsNullOrWhiteSpace(name))
        {
            network.ApplyShelves(shelf.Kind == ShelfType.Collection ? ShelfOp.RenameCollection(shelf.Id, name.Trim()) : ShelfOp.RenameList(shelf.Id, name.Trim()));
        }
    }

    private async Task DeleteAsync(NetworkServices network, Shelf shelf)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = string.Format(CultureInfo.CurrentCulture, Strings.Get("shelves_delete_title___"), shelf.Name),
            Content = new TextBlock
            {
                Text = Strings.Get(shelf.Kind == ShelfType.Collection ? "shelves_delete_collection_body" : "shelves_delete_list_body"),
                TextWrapping = TextWrapping.Wrap,
            },
            PrimaryButtonText = Strings.Get("shelves_delete"),
            CloseButtonText = Strings.Get("shelves_cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            network.ApplyShelves(shelf.Kind == ShelfType.Collection ? ShelfOp.DeleteCollection(shelf.Id) : ShelfOp.DeleteList(shelf.Id));
        }
    }

    private async Task<string?> AskNameAsync(string title, string initial, string confirm)
    {
        var field = new TextBox { Text = initial, Header = Strings.Get("shelves_new_field") };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = field,
            PrimaryButtonText = confirm,
            CloseButtonText = Strings.Get("shelves_cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary ? field.Text : null;
    }
}
