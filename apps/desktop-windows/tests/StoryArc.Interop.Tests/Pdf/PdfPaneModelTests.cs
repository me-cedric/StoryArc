using StoryArc.Interop.Pdf;

namespace StoryArc.Interop.Tests.Pdf;

/// <summary>The contents pane rules of desktop-clients task 4.17: the outline flattened, search rows by page, and nothing offered without a text layer.</summary>
public sealed class PdfPaneModelTests
{
    private static readonly IReadOnlyList<PdfOutlineEntry> Outline =
    [
        new("Part One", null, [new("Chapter One", 0, []), new("Chapter Two", 1, [])]),
        new("Chapter Three", 2, []),
    ];

    [Fact]
    public void The_outline_flattens_in_reading_order_with_its_depth_and_page_numbers_from_one()
    {
        var pane = new PdfPaneModel(hasTextLayer: true, Outline, _ => []);

        var rows = pane.OutlineRows("Page {0}");

        Assert.Equal(new[] { "Part One", "Chapter One", "Chapter Two", "Chapter Three" }, rows.Select(row => row.Title));
        Assert.Equal(new[] { 0, 1, 1, 0 }, rows.Select(row => row.Depth));
        Assert.Equal(new[] { "", "Page 1", "Page 2", "Page 3" }, rows.Select(row => row.Detail));
        Assert.Null(rows[0].PageIndex);
        Assert.Equal(2, rows[3].PageIndex);
    }

    [Fact]
    public void A_search_lists_each_page_with_its_hit_count_and_a_blank_query_asks_nothing()
    {
        var asked = new List<string>();
        var pane = new PdfPaneModel(hasTextLayer: true, Outline, query =>
        {
            asked.Add(query);
            return [new PdfSearchHit(1, [new PdfRect(1, 1, 2, 2), new PdfRect(3, 3, 4, 4)]), new PdfSearchHit(2, [new PdfRect(1, 1, 2, 2)])];
        });

        var rows = pane.SearchRows("  chapter ", "Page {0}", "{0} matches");

        Assert.Equal(new[] { "chapter" }, asked);
        Assert.Equal(new[] { ("Page 2", "2 matches", 1), ("Page 3", "1 matches", 2) }, rows.Select(row => (row.Title, row.Detail, row.PageIndex!.Value)));
        Assert.Empty(pane.SearchRows("   ", "Page {0}", "{0} matches"));
        Assert.Single(asked);
    }

    [Fact]
    public void A_scanned_file_offers_neither_search_nor_selection_and_the_engine_is_not_asked()
    {
        var asked = 0;
        var pane = new PdfPaneModel(hasTextLayer: false, [], _ =>
        {
            asked++;
            return [];
        });

        Assert.False(pane.HasTextLayer);
        Assert.False(pane.HasOutline);
        Assert.False(pane.IsAvailable);
        Assert.Empty(pane.SearchRows("anything", "Page {0}", "{0}"));
        Assert.Equal(0, asked);
    }

    [Fact]
    public void A_scanned_file_with_an_outline_still_offers_the_outline()
    {
        var pane = new PdfPaneModel(hasTextLayer: false, Outline, _ => []);

        Assert.True(pane.IsAvailable);
        Assert.Equal(4, pane.OutlineRows("Page {0}").Count);
    }

    [Fact]
    public void The_outline_row_of_a_page_is_the_last_entry_at_or_before_it()
    {
        var pane = new PdfPaneModel(hasTextLayer: true, Outline, _ => []);

        Assert.Equal(1, pane.OutlineRowFor(0, "Page {0}"));
        Assert.Equal(2, pane.OutlineRowFor(1, "Page {0}"));
        Assert.Equal(3, pane.OutlineRowFor(7, "Page {0}"));
        Assert.Null(new PdfPaneModel(true, [new PdfOutlineEntry("Nowhere", null, [])], _ => []).OutlineRowFor(0, "Page {0}"));
    }

    [Fact]
    public void A_press_that_tries_to_select_in_a_scanned_file_is_told_the_file_is_images_of_pages()
    {
        var scanned = new PdfPaneModel(hasTextLayer: false, [], _ => []);
        var text = new PdfPaneModel(hasTextLayer: true, [], _ => []);

        Assert.True(scanned.TellsImagesOnly(12));
        Assert.True(scanned.TellsImagesOnly(-20));
        Assert.True(scanned.TellsImagesOnly(0, isSecondaryPress: true));
        // A click is a page zone, and a long drag turns the page: neither is a selection.
        Assert.False(scanned.TellsImagesOnly(2));
        Assert.False(scanned.TellsImagesOnly(StoryArc.Interop.Reader.DragTurn.Threshold));
        Assert.False(text.TellsImagesOnly(12, isSecondaryPress: true));
    }
}
