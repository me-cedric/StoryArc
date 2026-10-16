using StoryArc.Interop.Library;

namespace StoryArc.Interop.Tests.Library;

/// <summary>
/// Search, filters and sorting, test first (desktop-clients task 2.47b, after 2.23b): the field
/// stays in place while its results take over the content column, the four filters, the sort keys.
/// </summary>
public sealed class LibraryQueryStateTests
{
    private static readonly DateTimeOffset Day = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);

    private static readonly LibraryRecord[] Records =
    [
        new("saga1", "Saga 1", "Saga", 1, "Brian K. Vaughan", PublicationFormat.Cbz, "folder", 1.0, true, Day, Day.AddDays(1), 2012, 50, null),
        new("saga2", "Saga 2", "Saga", 2, "Brian K. Vaughan", PublicationFormat.Cbz, "folder", 0.4, false, Day.AddDays(1), Day.AddDays(3), 2012, 60, null),
        new("lumiere", "Lumière", null, null, "Anne", PublicationFormat.Epub, "opds", 0, true, Day.AddDays(2), null, 2020, 10, null),
        new("fine", "Fine Print", "Fine Print", 1, "Stjepan Šejić", PublicationFormat.Pdf, "kavita", 0, false, Day.AddDays(3), Day, 2021, 90, null),
    ];

    [Fact]
    public void The_field_stays_in_place_and_the_results_take_over_the_content_while_text_is_in_it()
    {
        var state = new LibraryQueryState();
        state.Navigate(LibraryDestination.Library);

        Assert.False(state.IsShowingResults);
        Assert.Equal(LibraryDestination.Library, state.ContentDestination);

        state.SetSearchText("sa");
        Assert.True(state.IsShowingResults);
        Assert.Equal(LibraryDestination.Search, state.ContentDestination);

        state.ClearSearch();
        Assert.False(state.IsShowingResults);
        Assert.Equal(LibraryDestination.Library, state.ContentDestination);
    }

    [Fact]
    public void Whitespace_alone_is_not_a_search()
    {
        var state = new LibraryQueryState();
        state.SetSearchText("   ");

        Assert.False(state.IsShowingResults);
        Assert.Equal(LibraryDestination.Home, state.ContentDestination);
    }

    [Fact]
    public void Choosing_a_destination_in_the_pane_ends_the_search()
    {
        var state = new LibraryQueryState();
        state.SetSearchText("saga");

        state.Navigate(LibraryDestination.Downloads);

        Assert.Equal(string.Empty, state.SearchText);
        Assert.Equal(LibraryDestination.Downloads, state.ContentDestination);
    }

    [Fact]
    public void Search_matches_title_series_and_author_folded_for_accents()
    {
        var state = new LibraryQueryState();

        state.SetSearchText("lumiere");
        Assert.Equal<string>(new[] { "lumiere" }, state.Apply(Records).Select(record => record.Id));

        state.SetSearchText("vaughan");
        Assert.Equal<string>(new[] { "saga1", "saga2" }, state.Apply(Records).Select(record => record.Id));

        state.SetSearchText("SEJIC");
        Assert.Equal<string>(new[] { "fine" }, state.Apply(Records).Select(record => record.Id));
    }

    [Fact]
    public void Filters_by_format_source_reading_state_and_download_state_stack()
    {
        var state = new LibraryQueryState { Filters = new LibraryFilters(PublicationFormat.Cbz, null, null, null) };
        Assert.Equal(2, state.Apply(Records).Count);

        state.Filters = state.Filters with { IsDownloaded = true };
        Assert.Equal<string>(new[] { "saga1" }, state.Apply(Records).Select(record => record.Id));
        Assert.Equal(2, state.Filters.ActiveCount);

        state.Filters = new LibraryFilters(null, "kavita", null, null);
        Assert.Equal<string>(new[] { "fine" }, state.Apply(Records).Select(record => record.Id));

        state.Filters = new LibraryFilters(null, null, ReadingState.InProgress, null);
        Assert.Equal<string>(new[] { "saga2" }, state.Apply(Records).Select(record => record.Id));

        state.Filters = LibraryFilters.None;
        Assert.Equal(0, state.Filters.ActiveCount);
        Assert.Equal(4, state.Apply(Records).Count);
    }

    [Fact]
    public void Sort_keys_order_the_results_and_descending_reverses_them()
    {
        var state = new LibraryQueryState { Sort = SortKey.Title };
        Assert.Equal<string>(new[] { "fine", "lumiere", "saga1", "saga2" }, state.Apply(Records).Select(record => record.Id));

        state.Sort = SortKey.DateAdded;
        state.SortDescending = true;
        Assert.Equal<string>(new[] { "fine", "lumiere", "saga2", "saga1" }, state.Apply(Records).Select(record => record.Id));

        state.Sort = SortKey.LastRead;
        Assert.Equal<string>(new[] { "saga2", "saga1", "fine", "lumiere" }, state.Apply(Records).Select(record => record.Id));

        state.Sort = SortKey.Progress;
        state.SortDescending = false;
        Assert.Equal<string>(new[] { "fine", "lumiere", "saga2", "saga1" }, state.Apply(Records).Select(record => record.Id));

        state.Sort = SortKey.FileSize;
        Assert.Equal<string>(new[] { "lumiere", "saga1", "saga2", "fine" }, state.Apply(Records).Select(record => record.Id));

        state.Sort = SortKey.Series;
        Assert.Equal<string>(new[] { "fine", "lumiere", "saga1", "saga2" }, state.Apply(Records).Select(record => record.Id));
    }
}
