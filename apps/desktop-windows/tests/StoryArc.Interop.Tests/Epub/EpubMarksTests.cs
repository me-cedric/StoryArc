using System.Text.Json.Nodes;
using StoryArc.Interop.Epub;

namespace StoryArc.Interop.Tests.Epub;

/// <summary>
/// The EPUB reader's navigation and marks on Windows (<c>ebook-reader</c>, "Navigation and annotation", "Pagination and
/// progress"): the contents to full depth, bookmarks and highlights kept per publication, the renderer's selection,
/// footnote and search messages, the way back after a jump, and the progress line.
/// </summary>
public sealed class EpubMarksTests
{
    private const string One = """{"href":"OEBPS/ch1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.25,"totalProgression":0.1}}""";
    private const string Two = """{"href":"OEBPS/ch2.xhtml#n1","type":"application/xhtml+xml","locations":{"progression":0.5,"totalProgression":0.6}}""";

    private static readonly DateTimeOffset Now = new(2026, 10, 18, 12, 0, 0, TimeSpan.Zero);

    private static int Order(string href) => href == "OEBPS/ch1.xhtml" ? 0 : 1;

    [Fact]
    public void The_contents_are_shown_to_full_depth_with_the_current_chapter_found()
    {
        const string manifest = """
            {"toc":[{"href":"OEBPS/ch1.xhtml","title":"One"},
                    {"href":"OEBPS/ch2.xhtml","title":"Two","children":[{"href":"OEBPS/ch2.xhtml#n1","title":"Two, a"},{"href":"OEBPS/ch3.xhtml"}]}]}
            """;

        var entries = EpubContents.Of(manifest);

        Assert.Equal(new[] { "One", "Two", "Two, a", "OEBPS/ch3.xhtml" }, entries.Select(entry => entry.Title));
        Assert.Equal(new[] { 0, 0, 1, 1 }, entries.Select(entry => entry.Depth));
        Assert.Equal(1, EpubContents.CurrentIndex(entries, Two));
        Assert.Equal("Two", EpubContents.ChapterTitle(entries, Two));
        Assert.Equal(-1, EpubContents.CurrentIndex(entries, """{"href":"OEBPS/other.xhtml"}"""));
        Assert.Empty(EpubContents.Of("{}"));
        Assert.Equal("OEBPS/ch2.xhtml#n1", JsonNode.Parse(entries[2].Locator)!["href"]!.GetValue<string>());
    }

    [Fact]
    public void A_bookmark_keeps_its_chapter_and_excerpt_toggles_off_and_lists_in_reading_order()
    {
        string? file = null;
        var marks = new EpubMarks(() => file, text => file = text, Order);

        Assert.True(marks.ToggleBookmark(Two, "Two", "The second.", Now));
        Assert.True(marks.ToggleBookmark(One, "One", "The first.", Now));

        var reopened = new EpubMarks(() => file, text => file = text, Order);
        Assert.Equal(new[] { "One", "Two" }, reopened.Bookmarks.Select(mark => mark.Chapter));
        Assert.Equal("The first.", reopened.Bookmarks[0].Excerpt);
        Assert.Equal("OEBPS/ch2.xhtml", reopened.Bookmarks[1].Href);
        Assert.NotNull(reopened.BookmarkAt(One));

        Assert.False(reopened.ToggleBookmark(One, "One", string.Empty, Now));
        Assert.Null(reopened.BookmarkAt(One));
        reopened.RemoveBookmark(reopened.Bookmarks[0].Id);
        Assert.Empty(new EpubMarks(() => file, text => file = text, Order).Bookmarks);
    }

    [Fact]
    public void A_selection_becomes_a_highlight_with_a_note_drawn_with_the_spoken_sentence_and_exported()
    {
        string? file = null;
        var marks = new EpubMarks(() => file, text => file = text, Order);
        var selection = RendererMessage.TryParse("""{"type":"selection","seq":4,"text":"  Call me Ishmael.  ","locator":""" + One + "}")!.Selection();
        Assert.Equal("Call me Ishmael.", selection!.Text);
        Assert.Null(RendererMessage.TryParse("""{"type":"selection","seq":5,"text":" "}""")!.Selection());

        var highlight = marks.AddHighlight(selection, HighlightColour.Green, "One", Now);
        marks.SetNote(highlight.Id, " A name. ");

        var reopened = new EpubMarks(() => file, text => file = text, Order);
        Assert.Equal("A name.", reopened.Highlight(highlight.Id)!.Note);
        var spoken = EpubMarks.SpokenLocator("Spoken.", "OEBPS/ch1.xhtml#start");
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse("""{"href":"OEBPS/ch1.xhtml","type":"application/xhtml+xml","locations":{},"text":{"highlight":"Spoken."}}"""), JsonNode.Parse(spoken)), spoken);
        var items = reopened.HighlightItems(spoken);
        Assert.Equal(2, items.Count);
        Assert.Equal("green", items[0]!["color"]!.GetValue<string>());
        Assert.Equal(EpubMarks.SpokenId, items[1]!["id"]!.GetValue<string>());
        Assert.Equal(EpubMarks.SpokenTint, items[1]!["color"]!.GetValue<string>());
        Assert.Contains("\"type\":\"highlights\"", new HostCommands().Highlights(items), StringComparison.Ordinal);

        Assert.Equal("# Moby-Dick\n\n## One\n\n> Call me Ishmael.\n\nA name.\n", reopened.Export("Moby-Dick", markdown: true));
        Assert.Equal("Moby-Dick\n\nOne\n\n“Call me Ishmael.”\nA name.\n", reopened.Export("Moby-Dick", markdown: false));

        reopened.SetNote(highlight.Id, string.Empty);
        Assert.Equal(string.Empty, reopened.Highlight(highlight.Id)!.Note);
        reopened.RemoveHighlight(highlight.Id);
        Assert.Empty(new EpubMarks(() => file, text => file = text, Order).Highlights);
    }

    [Fact]
    public void A_damaged_marks_file_opens_empty_and_a_failed_write_keeps_the_marks()
    {
        var marks = new EpubMarks(() => "{ broken", _ => throw new IOException("disk full"), Order);

        Assert.True(marks.ToggleBookmark(One, "One", string.Empty, Now));
        Assert.Single(marks.Bookmarks);
    }

    [Fact]
    public void Footnotes_activations_and_search_results_are_read_from_the_renderer()
    {
        var note = RendererMessage.TryParse("""{"type":"footnote","seq":1,"href":"OEBPS/notes.xhtml#n1","text":"A note."}""")!.Footnote();
        Assert.Equal(new EpubFootnote("OEBPS/notes.xhtml#n1", "A note."), note);
        Assert.Equal("h-1", RendererMessage.TryParse("""{"type":"highlight-activated","seq":2,"id":"h-1"}""")!.ActivatedId());

        var results = RendererMessage.TryParse("""
            {"type":"search-results","seq":3,"id":"s2","done":false,"results":[
              {"locator":{"href":"OEBPS/ch1.xhtml","title":"One","locations":{"progression":0.3},"text":{"before":"Call ","highlight":"me","after":" Ishmael"}}}]}
            """)!;
        Assert.Equal("s2", results.SearchId());
        Assert.False(results.SearchDone());
        var hit = Assert.Single(results.SearchHits());
        Assert.Equal(("One", "Call ", "me", " Ishmael"), (hit.Chapter, hit.Before, hit.Match, hit.After));
        Assert.Equal("OEBPS/ch1.xhtml", EpubPlace.Of(hit.Locator).Href);
        Assert.True(RendererMessage.TryParse("""{"type":"search-results","seq":4,"id":"s2","done":true,"results":[]}""")!.SearchDone());
        var moved = RendererMessage.TryParse("""{"type":"locator","seq":5,"locator":""" + One + "}")!.LocatorJson();
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(One), JsonNode.Parse(moved!)), moved);
    }

    [Fact]
    public void A_jump_offers_one_way_back_that_is_not_itself_a_place_to_return_from()
    {
        var jumps = new EpubJumps();
        jumps.Moved(One);
        Assert.Null(jumps.Return);

        // A page turn across a chapter is not a jump.
        jumps.Turning();
        jumps.Moved(Two);
        Assert.Null(jumps.Return);

        // A contents entry, a bookmark or a search hit is.
        jumps.Jumping();
        jumps.Moved(One);
        Assert.Equal(Two, jumps.Return);

        // Going back clears it, and the move back offers no return of its own.
        Assert.Equal(Two, jumps.Back());
        jumps.Moved(Two);
        Assert.Null(jumps.Return);
        Assert.Null(jumps.Back());

        // A link the reader followed into another chapter, which the app did not ask for.
        jumps.Moved(One);
        Assert.Equal(Two, jumps.Return);

        // A move within one chapter that the app did not ask for is not.
        var within = new EpubJumps();
        within.Moved(One);
        within.Moved(One.Replace("0.25", "0.5", StringComparison.Ordinal));
        Assert.Null(within.Return);
    }

    [Fact]
    public void The_progress_line_states_the_book_and_the_chapter_in_words_or_the_book_alone()
    {
        Assert.Equal("60% read · 50% of this chapter left", EpubProgressLine.Text("{0}% read · {1}% of this chapter left", "{0}% read", 0.6, 0.5, declaresChapters: true));
        Assert.Equal("60% read", EpubProgressLine.Text("{0}% read · {1}% of this chapter left", "{0}% read", 0.6, 0.5, declaresChapters: false));
        Assert.Equal("100% read · 0% of this chapter left", EpubProgressLine.Text("{0}% read · {1}% of this chapter left", "{0}% read", 1.2, 1.4, declaresChapters: true));
        Assert.Equal(new EpubPlace("OEBPS/ch2.xhtml", 0.5, 0.6), EpubPlace.Of(Two));
        Assert.Equal("The second one.", EpubMarks.ExcerptAt(["The first one.", "The second one."], 0.6));
        Assert.Equal(string.Empty, EpubMarks.ExcerptAt([], 0.5));
    }
}
