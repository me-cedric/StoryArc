using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using StoryArc.Interop.Epub;
using StoryArc.Windows.Shell;
using Windows.ApplicationModel.DataTransfer;

namespace StoryArc.Windows;

/// <summary>
/// Moving around the EPUB and marking places in it (<c>ebook-reader</c>, "Navigation and annotation"): the contents to full
/// depth with the current chapter selected, search with each match in its context, the bookmark of this page, the bookmarks
/// and highlights listed in one place and copied out as plain text or Markdown, what a selection offers, the note a footnote
/// shows in place, and the way back after each of these jumps. The records are <see cref="EpubMarks"/>; this file draws them.
/// </summary>
public sealed partial class EpubReaderWindow
{
    private int _searchCount;
    private string? _searchId;
    private int _searchHits;
    private EpubSelection? _selection;

    // Contents.

    private void OnContentsOpening(object? sender, object args)
    {
        ContentsList.Items.Clear();
        ContentsEmpty.Text = Strings.Get("contents_empty", "This book declares no table of contents.");
        ContentsEmpty.Visibility = _opened.Contents.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var entry in _opened.Contents)
        {
            var row = new TextBlock { Text = entry.Title, Margin = new Thickness(entry.Depth * 16, 0, 0, 0), TextWrapping = TextWrapping.Wrap, Tag = entry.Locator };
            AutomationProperties.SetLevel(row, entry.Depth + 1);
            ContentsList.Items.Add(row);
        }

        ContentsList.SelectedIndex = EpubContents.CurrentIndex(_opened.Contents, _jumps.Current);
    }

    private void OnContentsItem(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is FrameworkElement { Tag: string locator })
        {
            ContentsFlyout.Hide();
            Jump(locator);
        }
    }

    // Search.

    private void OnSearchOpened(object? sender, object args) => SearchBox.Focus(FocusState.Programmatic);

    private void OnSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args) => Search(args.QueryText);

    /// <summary>Searches the book; a newer search silences an older one, as the renderer promises.</summary>
    private void Search(string query)
    {
        SearchList.Items.Clear();
        _searchHits = 0;
        var trimmed = query.Trim();
        if (trimmed.Length == 0)
        {
            _searchId = null;
            SearchStatus.Text = string.Empty;
            return;
        }

        _searchId = "s" + (++_searchCount).ToString(CultureInfo.InvariantCulture);
        SearchStatus.Text = Strings.Get("search_running", "Searching…");
        Post(_commands.Search(_searchId, trimmed));
    }

    private void ReceiveSearch(StoryArc.Interop.Epub.RendererMessage message)
    {
        if (message.SearchId() != _searchId || _searchId is null)
        {
            return;
        }

        foreach (var hit in message.SearchHits())
        {
            _searchHits++;
            var row = new StackPanel { Spacing = 2, Tag = hit.Locator };
            if (hit.Chapter is { Length: > 0 } chapter)
            {
                row.Children.Add(new TextBlock { Text = chapter, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] });
            }

            var context = new TextBlock { TextWrapping = TextWrapping.Wrap };
            context.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = hit.Before });
            context.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = hit.Match, FontWeight = Microsoft.UI.Text.FontWeights.Bold });
            context.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = hit.After });
            row.Children.Add(context);
            AutomationProperties.SetName(row, hit.Before + hit.Match + hit.After);
            SearchList.Items.Add(row);
        }

        if (message.SearchDone())
        {
            SearchStatus.Text = _searchHits == 0
                ? string.Format(CultureInfo.CurrentCulture, Strings.Get("search_none___", "Nothing found for “{0}”."), SearchBox.Text.Trim())
                : string.Empty;
        }
    }

    private void OnSearchItem(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is FrameworkElement { Tag: string locator })
        {
            SearchFlyout.Hide();
            Jump(locator);
        }
    }

    // Bookmarks.

    private void OnBookmarkToggled(object sender, RoutedEventArgs args) => ToggleBookmark();

    /// <summary>Bookmarks the page being read with its chapter and an excerpt, or removes the bookmark already there.</summary>
    private void ToggleBookmark()
    {
        if (_jumps.Current is not { } locator)
        {
            ShowBookmark();
            return;
        }

        var place = EpubPlace.Of(locator);
        var order = OrderOf(place.Href);
        var sentences = order < _opened.ReadingOrder.Count ? _opened.SentencesOf(order).Select(sentence => sentence.Text).ToList() : new List<string>();
        _ = _marks.ToggleBookmark(locator, ChapterAt(locator), EpubMarks.ExcerptAt(sentences, place.Progression), DateTimeOffset.Now);
        ShowBookmark();
    }

    private void ShowBookmark()
    {
        var marked = _jumps.Current is { } locator && _marks.BookmarkAt(locator) is not null;
        BookmarkButton.IsChecked = marked;
        var text = marked ? Strings.Get("bookmarks_remove", "Remove bookmark") : Strings.Get("bookmarks_add", "Bookmark this page");
        BookmarkButton.Label = text;
        ToolTipService.SetToolTip(BookmarkButton, text);
    }

    /// <summary>The chapter a place is in: the contents' title for it, or the reading order's.</summary>
    private string ChapterAt(string locator)
    {
        if (EpubContents.ChapterTitle(_opened.Contents, locator) is { } title)
        {
            return title;
        }

        var order = OrderOf(EpubPlace.Of(locator).Href);
        return order < _opened.ReadingOrder.Count ? _opened.ReadingOrder[order].Title : Strings.Get("bookmarks_unnamed", "Unnamed chapter");
    }

    // Bookmarks and highlights, in one place.

    private void OnMarksOpening(object? sender, object args) => ShowMarks();

    private void ShowMarks()
    {
        MarksPanel.Children.Clear();
        MarksPanel.Children.Add(Heading(Strings.Get("bookmarks_title", "Bookmarks")));
        if (_marks.Bookmarks.Count == 0)
        {
            MarksPanel.Children.Add(Quiet(Strings.Get("reader_bookmark_empty", "No pages bookmarked yet.")));
        }

        foreach (var mark in _marks.Bookmarks)
        {
            var remove = IconButton("", Strings.Get("bookmarks_remove", "Remove bookmark"), () =>
            {
                _marks.RemoveBookmark(mark.Id);
                ShowBookmark();
                ShowMarks();
            });
            MarksPanel.Children.Add(Row(mark.Chapter, mark.Excerpt, null, mark.Locator, remove));
        }

        MarksPanel.Children.Add(Heading(Strings.Get("desktop_w4_epub_highlights", "Highlights")));
        if (_marks.Highlights.Count == 0)
        {
            MarksPanel.Children.Add(Quiet(Strings.Get("annotations_empty", "Nothing marked yet. Select a word or a passage and a menu offers a colour.")));
        }

        foreach (var mark in _marks.Highlights)
        {
            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            actions.Children.Add(IconButton("", Strings.Get("annotations_note", "Note"), () =>
            {
                MarksFlyout.Hide();
                _ = EditHighlightAsync(mark);
            }));
            actions.Children.Add(IconButton("", Strings.Get("annotations_remove", "Remove"), () =>
            {
                _marks.RemoveHighlight(mark.Id);
                SyncHighlights();
                ShowMarks();
            }));
            MarksPanel.Children.Add(Row(mark.Chapter, mark.Text, mark.Note.Length > 0 ? mark.Note : null, mark.Locator, actions, mark.Colour));
        }

        if (_marks.Highlights.Count > 0)
        {
            var export = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            export.Children.Add(TextButton(Strings.Get("desktop_w4_epub_copyText", "Copy as Text"), () => Copy(_marks.Export(_opened.Title, markdown: false))));
            export.Children.Add(TextButton(Strings.Get("desktop_w4_epub_copyMarkdown", "Copy as Markdown"), () => Copy(_marks.Export(_opened.Title, markdown: true))));
            MarksPanel.Children.Add(export);
        }
    }

    /// <summary>One mark: a button that jumps to it, naming its chapter and its text, with its own actions beside it.</summary>
    private Grid Row(string chapter, string text, string? note, string locator, UIElement actions, HighlightColour? colour = null)
    {
        var body = new StackPanel { Spacing = 2 };
        body.Children.Add(new TextBlock { Text = chapter, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"], TextWrapping = TextWrapping.Wrap });
        if (text.Length > 0)
        {
            body.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, MaxLines = 3, TextTrimming = TextTrimming.WordEllipsis });
        }

        if (note is not null)
        {
            body.Children.Add(new TextBlock { Text = note, TextWrapping = TextWrapping.Wrap, FontStyle = global::Windows.UI.Text.FontStyle.Italic });
        }

        var open = new Button { Content = body, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(colour is null ? 0 : 4, 0, 0, 0) };
        if (colour is { } tint)
        {
            open.BorderBrush = new SolidColorBrush(TintOf(tint));
        }

        AutomationProperties.SetName(open, chapter + ". " + text + (note is null ? string.Empty : ". " + note));
        open.Click += (sender, args) =>
        {
            MarksFlyout.Hide();
            Jump(locator);
        };

        var row = new Grid { ColumnSpacing = 4 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(open);
        Grid.SetColumn((FrameworkElement)actions, 1);
        row.Children.Add(actions);
        return row;
    }

    private static TextBlock Heading(string text) => new() { Text = text, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], Margin = new Thickness(0, 4, 0, 0) };

    private static TextBlock Quiet(string text) => new() { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] };

    private static Button IconButton(string glyph, string name, Action click)
    {
        var button = new Button { Content = new FontIcon { Glyph = glyph, FontSize = 14 }, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0) };
        AutomationProperties.SetName(button, name);
        ToolTipService.SetToolTip(button, name);
        button.Click += (sender, args) => click();
        return button;
    }

    private static Button TextButton(string text, Action click)
    {
        var button = new Button { Content = text };
        button.Click += (sender, args) => click();
        return button;
    }

    private static void Copy(string text)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
    }

    // What a selection offers: a highlight in five colours, a note, copy, and search in the publication.

    private void ShowSelection(EpubSelection? selection)
    {
        _selection = selection;
        SelectionBar.Children.Clear();
        SelectionBar.Visibility = selection is null ? Visibility.Collapsed : Visibility.Visible;
        if (selection is null)
        {
            return;
        }

        foreach (var colour in Enum.GetValues<HighlightColour>())
        {
            var name = Strings.Get("annotations_colour_" + colour.ToString().ToLowerInvariant(), colour.ToString());
            var swatch = new Button
            {
                Width = 32,
                Height = 32,
                Padding = new Thickness(0),
                Content = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 18, Height = 18, Fill = new SolidColorBrush(TintOf(colour)) },
            };
            var label = Strings.Get("desktop_w4_epub_highlight", "Highlight") + ", " + name;
            AutomationProperties.SetName(swatch, label);
            ToolTipService.SetToolTip(swatch, label);
            swatch.Click += (sender, args) => Highlight(colour);
            SelectionBar.Children.Add(swatch);
        }

        SelectionBar.Children.Add(TextButton(Strings.Get("annotations_note", "Note"), () =>
        {
            if (Highlight(HighlightColour.Yellow) is { } added)
            {
                _ = EditHighlightAsync(added);
            }
        }));
        SelectionBar.Children.Add(TextButton(Strings.Get("annotations_copy", "Copy"), () =>
        {
            if (_selection is { } chosen)
            {
                Copy(chosen.Text);
            }
        }));
        SelectionBar.Children.Add(TextButton(Strings.Get("reader_pdf_searchSelection", "Search for this"), () =>
        {
            if (_selection is { } chosen)
            {
                SearchBox.Text = chosen.Text;
                SearchFlyout.ShowAt(SearchButton);
                Search(chosen.Text);
            }
        }));
    }

    private EpubHighlight? Highlight(HighlightColour colour)
    {
        if (_selection is not { } chosen)
        {
            return null;
        }

        var added = _marks.AddHighlight(chosen, colour, ChapterAt(chosen.Locator), DateTimeOffset.Now);
        SyncHighlights();
        ShowSelection(null);
        return added;
    }

    /// <summary>A highlight's note, written or cleared, or the highlight removed.</summary>
    private async Task EditHighlightAsync(EpubHighlight highlight)
    {
        var box = new TextBox { Text = highlight.Note, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 96, Header = highlight.Text };
        AutomationProperties.SetName(box, Strings.Get("annotations_note", "Note"));
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = Strings.Get("annotations_note", "Note"),
            Content = box,
            PrimaryButtonText = Strings.Get("annotations_save", "Save"),
            SecondaryButtonText = Strings.Get("annotations_remove", "Remove"),
            CloseButtonText = Strings.Get("annotations_cancel", "Cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        switch (await dialog.ShowAsync())
        {
            case ContentDialogResult.Primary:
                _marks.SetNote(highlight.Id, box.Text);
                break;
            case ContentDialogResult.Secondary:
                _marks.RemoveHighlight(highlight.Id);
                SyncHighlights();
                break;
        }
    }

    /// <summary>A footnote opens in place, over the page; a note the renderer could not find is a jump with a way back.</summary>
    private void ShowFootnote(EpubFootnote note)
    {
        if (note.Text.Length == 0)
        {
            Jump(EpubContents.LocatorFor(note.Href));
            return;
        }

        var flyout = new Flyout
        {
            Content = new ScrollViewer { MaxHeight = 320, MaxWidth = 420, Content = new TextBlock { Text = note.Text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true } },
        };
        flyout.ShowAt(Web);
    }

    private static global::Windows.UI.Color TintOf(HighlightColour colour) => colour switch
    {
        HighlightColour.Green => Microsoft.UI.Colors.LightGreen,
        HighlightColour.Blue => Microsoft.UI.Colors.LightBlue,
        HighlightColour.Pink => Microsoft.UI.Colors.Pink,
        HighlightColour.Purple => Microsoft.UI.Colors.Plum,
        _ => Microsoft.UI.Colors.Yellow,
    };
}
