using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using StoryArc.Interop;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Pdf;
using StoryArc.Interop.Reader;
using StoryArc.Windows.Shell;
using Windows.ApplicationModel.DataTransfer;

namespace StoryArc.Windows;

/// <summary>
/// The text of a PDF page in the contents pane (ebook-reader, "Text-based PDF"). The page is drawn as an image, so the reader
/// selects in the engine's text of the page shown; a selection offers the five highlight colours, a note, copy and search in the
/// document, and is kept as the EPUB's own highlight record (<see cref="PdfMarks"/>, <see cref="EpubMarks"/>), listed below the
/// text and copied out by the same document. Absent for a scanned file, which has no text to select.
/// </summary>
public sealed partial class ReaderWindow
{
    private EpubMarks? _pdfMarks;
    private string _pageText = string.Empty;
    private int _pageTextShown = -1;

    /// <summary>The marks of this PDF, opened the first time the text pane is shown.</summary>
    private EpubMarks PdfMarksStore()
    {
        if (_pdfMarks is null)
        {
            var path = Path.Combine(StateFiles.PdfMarksFolder, (_opened.Record.Identity.ContentDigest ?? StoryArc.Interop.Epub.EpubHost.IdFor(_opened.Id)) + ".json");
            _pdfMarks = new EpubMarks(
                () => File.Exists(path) ? File.ReadAllText(path) : null,
                text =>
                {
                    Directory.CreateDirectory(StateFiles.PdfMarksFolder);
                    File.WriteAllText(path, text);
                },
                PdfMarks.PageOf);
        }

        return _pdfMarks;
    }

    /// <summary>Shows the page text section in the contents pane for a text PDF, and the text of the page shown.</summary>
    private async Task ShowPageTextAsync()
    {
        if (_opened.Pdf is not { HasTextLayer: true } pdf || ContentsPane.Visibility != Visibility.Visible)
        {
            return;
        }

        PageTextTitle.Text = Strings.Get("desktop_w4_pdf_pageText", "Page text");
        PageTextTitle.Visibility = Visibility.Visible;
        PageTextScroller.Visibility = Visibility.Visible;
        PdfMarksPanel.Visibility = Visibility.Visible;
        PageTextRow.Height = new GridLength(1, GridUnitType.Star);

        var page = _navigator.CurrentPage;
        if (page != _pageTextShown)
        {
            string text;
            try
            {
                text = await Task.Run(() => pdf.PageText(page));
            }
            catch (StoryArcException)
            {
                text = string.Empty;
            }
            catch (ObjectDisposedException)
            {
                return;
            }

            if (page != _navigator.CurrentPage)
            {
                return;
            }

            _pageTextShown = page;
            _pageText = text;
            PageTextBlock.Blocks.Clear();
            var paragraph = new Paragraph();
            paragraph.Inlines.Add(new Run { Text = text.Length == 0 ? Strings.Get("desktop_w4_pdf_noTextOnPage", "This page has no text.") : text });
            PageTextBlock.Blocks.Add(paragraph);
            ShowPdfSelection(null);
        }

        DrawPageHighlights();
        ShowPdfHighlights();
    }

    private void OnPageTextSelection(object sender, RoutedEventArgs args) =>
        ShowPdfSelection(PageTextBlock.SelectedText is { Length: > 0 } selected && _pageText.Length > 0 ? selected.Trim() : null);

    // What a selection offers: the five colours, a note, copy and search in the document.
    private void ShowPdfSelection(string? selected)
    {
        PdfSelectionBar.Children.Clear();
        PdfSelectionBar.Visibility = string.IsNullOrEmpty(selected) ? Visibility.Collapsed : Visibility.Visible;
        if (string.IsNullOrEmpty(selected))
        {
            return;
        }

        var colours = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        foreach (var colour in Enum.GetValues<HighlightColour>())
        {
            var name = Strings.Get("desktop_w4_epub_highlight", "Highlight") + ", " + Strings.Get("annotations_colour_" + colour.ToString().ToLowerInvariant(), colour.ToString());
            var swatch = new Button
            {
                Width = 32,
                Height = 32,
                Padding = new Thickness(0),
                Content = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 18, Height = 18, Fill = new SolidColorBrush(TintOf(colour)) },
            };
            AutomationProperties.SetName(swatch, name);
            ToolTipService.SetToolTip(swatch, name);
            swatch.Click += (sender, args) => HighlightPdf(selected, colour);
            colours.Children.Add(swatch);
        }

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        actions.Children.Add(PdfTextButton(Strings.Get("annotations_note", "Note"), () =>
        {
            if (HighlightPdf(selected, HighlightColour.Yellow) is { } added)
            {
                _ = EditPdfHighlightAsync(added);
            }
        }));
        actions.Children.Add(PdfTextButton(Strings.Get("annotations_copy", "Copy"), () => CopyText(selected)));
        actions.Children.Add(PdfTextButton(Strings.Get("reader_pdf_searchSelection", "Search for this"), () =>
        {
            PdfSearchBox.Text = selected;
            _ = SearchPdfAsync(selected);
        }));
        PdfSelectionBar.Children.Add(colours);
        PdfSelectionBar.Children.Add(actions);
    }

    private EpubHighlight? HighlightPdf(string selected, HighlightColour colour)
    {
        var page = _navigator.CurrentPage;
        var offset = PdfMarks.OffsetNear(_pageText, selected, PageTextBlock.SelectionStart?.Offset ?? 0);
        if (offset < 0)
        {
            return null;
        }

        var chapter = string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w4_pdf_page__lld", "Page {0}"), page + 1);
        var added = PdfMarksStore().AddHighlight(new EpubSelection(selected, PdfMarks.Locator(page, offset, selected)), colour, chapter, DateTimeOffset.Now);
        ShowPdfSelection(null);
        DrawPageHighlights();
        ShowPdfHighlights();
        return added;
    }

    /// <summary>The highlights of the page shown, drawn in its text in their colours.</summary>
    private void DrawPageHighlights()
    {
        PageTextBlock.TextHighlighters.Clear();
        foreach (var mark in PdfMarksStore().Highlights.Where(mark => PdfMarks.PageOf(mark.Href) == _pageTextShown))
        {
            if (PdfMarks.RangeIn(_pageText, mark) is { } range)
            {
                var highlighter = new TextHighlighter { Background = new SolidColorBrush(TintOf(mark.Colour)) };
                highlighter.Ranges.Add(new TextRange { StartIndex = range.Start, Length = range.Length });
                PageTextBlock.TextHighlighters.Add(highlighter);
            }
        }
    }

    /// <summary>Every highlight of the document by page, each going to its page, with its note and its actions, and the export.</summary>
    private void ShowPdfHighlights()
    {
        PdfHighlightsList.Children.Clear();
        var marks = PdfMarksStore();
        PdfHighlightsList.Children.Add(new TextBlock { Text = Strings.Get("desktop_w4_epub_highlights", "Highlights"), Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
        if (marks.Highlights.Count == 0)
        {
            PdfHighlightsList.Children.Add(new TextBlock
            {
                Text = Strings.Get("annotations_empty", "Nothing marked yet. Select a word or a passage and a menu offers a colour."),
                TextWrapping = TextWrapping.Wrap,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            });
            return;
        }

        foreach (var mark in marks.Highlights)
        {
            var body = new StackPanel { Spacing = 2 };
            body.Children.Add(new TextBlock { Text = mark.Chapter, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"] });
            body.Children.Add(new TextBlock { Text = mark.Text, TextWrapping = TextWrapping.Wrap, MaxLines = 3, TextTrimming = TextTrimming.WordEllipsis });
            if (mark.Note.Length > 0)
            {
                body.Children.Add(new TextBlock { Text = mark.Note, TextWrapping = TextWrapping.Wrap, FontStyle = global::Windows.UI.Text.FontStyle.Italic });
            }

            var open = new Button
            {
                Content = body,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                BorderBrush = new SolidColorBrush(TintOf(mark.Colour)),
                BorderThickness = new Thickness(4, 0, 0, 0),
            };
            AutomationProperties.SetName(open, mark.Chapter + ". " + mark.Text + (mark.Note.Length > 0 ? ". " + mark.Note : string.Empty));
            open.Click += (sender, args) =>
            {
                if (_navigator.GoTo(PdfMarks.PageOf(mark.Href)))
                {
                    _pages.ZoomTo(PageZoom.Floor, anchor: null);
                    PageMoved();
                }
            };
            var note = PdfTextButton(Strings.Get("annotations_note", "Note"), () => _ = EditPdfHighlightAsync(mark));
            var remove = PdfTextButton(Strings.Get("annotations_remove", "Remove"), () =>
            {
                marks.RemoveHighlight(mark.Id);
                DrawPageHighlights();
                ShowPdfHighlights();
            });
            var row = new StackPanel { Spacing = 2 };
            row.Children.Add(open);
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            actions.Children.Add(note);
            actions.Children.Add(remove);
            row.Children.Add(actions);
            PdfHighlightsList.Children.Add(row);
        }

        var export = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        export.Children.Add(PdfTextButton(Strings.Get("desktop_w4_epub_copyText", "Copy as Text"), () => CopyText(marks.Export(_opened.Record.DisplayTitle, markdown: false))));
        export.Children.Add(PdfTextButton(Strings.Get("desktop_w4_epub_copyMarkdown", "Copy as Markdown"), () => CopyText(marks.Export(_opened.Record.DisplayTitle, markdown: true))));
        PdfHighlightsList.Children.Add(export);
    }

    private async Task EditPdfHighlightAsync(EpubHighlight highlight)
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
                PdfMarksStore().SetNote(highlight.Id, box.Text);
                break;
            case ContentDialogResult.Secondary:
                PdfMarksStore().RemoveHighlight(highlight.Id);
                break;
        }

        DrawPageHighlights();
        ShowPdfHighlights();
    }

    private static Button PdfTextButton(string text, Action click)
    {
        var button = new Button { Content = text };
        button.Click += (sender, args) => click();
        return button;
    }

    private static void CopyText(string text)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
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
