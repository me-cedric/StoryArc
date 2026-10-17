using StoryArc.Interop.Library;
using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Tests.Library;

/// <summary>
/// The library grid and list, test first (desktop-clients task 2.47a, after 2.23a): an empty
/// library, 10,000 publications, grouping by series, single selection and modifier-click selection,
/// the cover ladder and the entry for a file that could not be opened.
/// </summary>
public sealed class LibraryViewModelTests
{
    private static readonly DateTimeOffset Epoch = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);

    internal static LibraryRecord Record(string id, string title, string? series = null, double? issue = null, double progress = 0, bool downloaded = false, string? unreadable = null) =>
        new(id, title, series, issue, "Author", PublicationFormat.Cbz, "folder", progress, downloaded, Epoch, null, 2020, 1_000_000, unreadable);

    private static IEnumerable<LibraryRecord> Corpus(int count) =>
        Enumerable.Range(0, count).Select(index => Record($"p{index}", $"Title {index:D5}", $"Series {index % 100}", index % 12 + 1));

    [Fact]
    public void An_empty_library_has_no_cells_and_no_selection()
    {
        var model = new LibraryViewModel();
        model.Load([]);

        Assert.True(model.IsEmpty);
        var section = Assert.Single(model.Sections());
        Assert.Empty(section.Cells);
        Assert.False(model.IsSelectionMode);
    }

    [Fact]
    public void Ten_thousand_publications_fill_the_grid_and_the_list_in_their_order()
    {
        var model = new LibraryViewModel();
        model.Load(Corpus(10_000));

        var grid = Assert.Single(model.Sections());
        Assert.Equal(10_000, grid.Cells.Count);
        Assert.Equal("Title 00000", grid.Cells[0].Title);
        Assert.Equal("Title 09999", grid.Cells[^1].Title);

        model.Presentation = LibraryPresentation.List;
        Assert.Equal(10_000, model.Sections().Sum(section => section.Cells.Count));
    }

    [Fact]
    public void Grouping_by_series_puts_each_series_under_its_heading_and_the_rest_last()
    {
        var model = new LibraryViewModel { GroupBySeries = true };
        model.Load([
            Record("a", "Alone"),
            Record("b", "Saga 2", "Saga", 2),
            Record("c", "Fine Print 1", "Fine Print", 1),
            Record("d", "Saga 1", "Saga", 1),
        ]);

        var sections = model.Sections();

        Assert.Equal<string?>(new string?[] { "Fine Print", "Saga", null }, sections.Select(section => section.Series));
        Assert.Equal<string>(new[] { "Saga 2", "Saga 1" }, sections[1].Cells.Select(cell => cell.Title));
        Assert.Equal("Alone", Assert.Single(sections[2].Cells).Title);
    }

    [Fact]
    public void A_click_selects_one_a_control_click_toggles_and_a_shift_click_selects_the_range()
    {
        var model = new LibraryViewModel();
        model.Load(Corpus(6));

        model.Select("p1");
        Assert.Equal<string>(new[] { "p1" }, model.Selected.Order(StringComparer.Ordinal));
        Assert.True(model.IsSelectionMode);

        model.ToggleSelect("p3");
        Assert.Equal<string>(new[] { "p1", "p3" }, model.Selected.Order(StringComparer.Ordinal));

        model.ToggleSelect("p1");
        Assert.Equal<string>(new[] { "p3" }, model.Selected.Order(StringComparer.Ordinal));

        // The anchor is the last clicked item, as in Explorer, so the range runs from p1.
        model.SelectRange("p5");
        Assert.Equal<string>(new[] { "p1", "p2", "p3", "p4", "p5" }, model.Selected.Order(StringComparer.Ordinal));

        model.Select("p4");
        model.SelectRange("p2");
        Assert.Equal<string>(new[] { "p2", "p3", "p4" }, model.Selected.Order(StringComparer.Ordinal));

        model.Select("p0");
        Assert.Equal(1, model.SelectedCount);

        model.ClearSelection();
        Assert.False(model.IsSelectionMode);
        model.SelectRange("p2");
        Assert.Equal<string>(new[] { "p2" }, model.Selected.Order(StringComparer.Ordinal));
    }

    [Fact]
    public void A_reload_keeps_the_selection_that_still_exists()
    {
        var model = new LibraryViewModel();
        model.Load(Corpus(4));
        model.Select("p1");
        model.ToggleSelect("p3");

        model.Load(Corpus(2));

        Assert.Equal<string>(new[] { "p1" }, model.Selected);
    }

    [Fact]
    public void The_cell_of_a_file_that_could_not_be_opened_names_the_reason()
    {
        var cell = LibraryViewModel.Cell(Record("x", "Broken.cb7", unreadable: "7z archives are not supported"));

        Assert.True(cell.IsUnreadable);
        Assert.Equal("7z archives are not supported", cell.UnreadableReason);
        Assert.Contains("7z archives are not supported", cell.AccessibleName);
    }

    [Fact]
    public void The_accessible_name_reads_title_series_issue_progress_and_download()
    {
        var cell = LibraryViewModel.Cell(Record("s4", "Saga 4", "Saga", 4, progress: 0.62, downloaded: true));

        Assert.Equal("Saga 4, Saga, issue 4, 62 percent read, downloaded", cell.AccessibleName);
        Assert.Equal("Saga", cell.Subtitle);
        Assert.Equal(0.62, cell.Progress);
    }

    [Fact]
    public void The_cover_ladder_climbs_from_placeholder_to_thumbnail_to_full_and_stops()
    {
        Assert.Equal(CoverStep.Thumbnail, LibraryViewModel.NextCoverStep(CoverStep.Placeholder));
        Assert.Equal(CoverStep.Full, LibraryViewModel.NextCoverStep(CoverStep.Thumbnail));
        Assert.Equal(CoverStep.Full, LibraryViewModel.NextCoverStep(CoverStep.Full));
    }
}
