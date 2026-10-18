using StoryArc.Interop.Epub;
using StoryArc.Interop.Pdf;

namespace StoryArc.Interop.Tests.Pdf;

/// <summary>
/// A selection in a text PDF (ebook-reader, "Text-based PDF"): kept as the EPUB's highlight record, found again in its page's
/// text, listed by page and exported by the same document.
/// </summary>
public sealed class PdfMarksTests
{
    private const string Page = "Call me Ishmael. Some years ago, never mind how long, call me again.";

    [Fact]
    public void A_pdf_selection_is_the_same_highlight_record_and_is_found_again_in_its_page()
    {
        string? file = null;
        var marks = new EpubMarks(() => file, text => file = text, PdfMarks.PageOf);
        var offset = PdfMarks.OffsetNear(Page, "call me", 50);
        Assert.Equal(54, offset);
        Assert.Equal(-1, PdfMarks.OffsetNear(Page, "whale", 0));

        var highlight = marks.AddHighlight(new EpubSelection("call me", PdfMarks.Locator(2, offset, "call me")), HighlightColour.Pink, "Page 3", DateTimeOffset.UnixEpoch);
        marks.SetNote(highlight.Id, "Again.");
        marks.AddHighlight(new EpubSelection("Call", PdfMarks.Locator(0, 0, "Call")), HighlightColour.Yellow, "Page 1", DateTimeOffset.UnixEpoch);

        var reopened = new EpubMarks(() => file, text => file = text, PdfMarks.PageOf);
        Assert.Equal(new[] { "page-0", "page-2" }, reopened.Highlights.Select(mark => mark.Href));
        Assert.Equal((54, 7), PdfMarks.RangeIn(Page, reopened.Highlights[1])!.Value);
        // The page's text moved: the passage is found where it now is.
        Assert.Equal((0, 4), PdfMarks.RangeIn("Call me", reopened.Highlights[0] with { Locator = PdfMarks.Locator(0, 40, "Call") })!.Value);
        Assert.Null(PdfMarks.RangeIn("Nothing here", reopened.Highlights[1]));
        Assert.Contains("> call me\n\nAgain.", reopened.Export("A PDF", markdown: true), StringComparison.Ordinal);
        Assert.Equal(2, PdfMarks.PageOf(PdfMarks.Href(2)));
        Assert.Equal(int.MaxValue, PdfMarks.PageOf("OEBPS/ch1.xhtml"));
    }

    [Fact]
    public void A_scanned_file_has_no_page_text_and_the_engine_is_not_asked()
    {
        var asked = 0;
        var scanned = new PdfPaneModel(hasTextLayer: false, [], _ => [], _ => { asked++; return "text"; });
        var text = new PdfPaneModel(hasTextLayer: true, [], _ => [], index => "page " + index);

        Assert.Equal(string.Empty, scanned.PageText(0));
        Assert.Equal(0, asked);
        Assert.Equal("page 4", text.PageText(4));
    }
}
