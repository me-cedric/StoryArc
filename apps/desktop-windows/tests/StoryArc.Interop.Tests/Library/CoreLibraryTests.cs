using StoryArc.Interop.Library;

namespace StoryArc.Interop.Tests.Library;

/// <summary>
/// The library over the seam (tasks 2.47a, 2.47c and 2.47d): a core record becomes a library
/// record, Home's two shelves keep the order of storyarc-core's <c>continue_reading</c> and
/// <c>up_next</c>, and the detail page answers a publication with no cover, with progress and on an
/// offline source.
/// </summary>
public sealed class CoreLibraryTests
{
    private static readonly DateTimeOffset Day = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);

    private static LibraryRecord Issue(string id, string? series, double? number, double progress = 0, DateTimeOffset? lastRead = null) =>
        new(id, id, series, number, null, PublicationFormat.Cbz, "folder", progress, true, Day, lastRead, null, 1, null);

    [Fact]
    public void A_folder_of_the_corpus_becomes_library_records_keyed_by_path()
    {
        using var folder = Corpus.TemporaryFolder();
        var path = folder.Copy("comics/manga-metadata.cbz");
        using var source = ComicFolder.Open(folder.FullPath);

        var record = CoreLibrary.Record(Assert.Single(source.Records()), null, "folder-1");

        Assert.NotNull(record);
        // The core may resolve the temporary folder's links, so the name and the rootedness are what hold.
        Assert.Equal(Path.GetFileName(path), Path.GetFileName(record.Id));
        Assert.True(Path.IsPathRooted(record.Id));
        Assert.Equal("The Third Chapter", record.Title);
        Assert.Equal("Fixture Manga", record.Series);
        Assert.Equal(3, record.IssueNumber);
        Assert.Equal("First Writer", record.Author);
        Assert.Equal(PublicationFormat.Cbz, record.Format);
        Assert.Equal("folder-1", record.SourceId);
        Assert.Equal(2026, record.Year);
        Assert.Equal(ReadingState.Unread, record.ReadingState);
        Assert.True(record.IsDownloaded);
        Assert.NotNull(record.Core);
    }

    [Fact]
    public void A_progress_record_gives_the_fraction_and_the_moment_last_read()
    {
        var core = new CorePublication(new CoreIdentity(NormalizedPath: "/c/a.cbz"), "cbz", "A", PageCount: 5);
        var progress = CoreProgress.Page(core.Identity, 2, 5, Day);

        var record = CoreLibrary.Record(core, progress, "f")!;

        Assert.Equal(0.5, record.Progress);
        Assert.Equal(Day, record.LastReadAt);
        Assert.Equal(ReadingState.InProgress, record.ReadingState);
    }

    [Theory]
    [InlineData("3", 3.0)]
    [InlineData("3.5", 3.5)]
    [InlineData("Annual 1", 1.0)]
    [InlineData("", null)]
    [InlineData("Special", null)]
    public void The_issue_number_reads_the_digits_as_the_core_does(string number, double? expected)
    {
        Assert.Equal(expected, CoreLibrary.IssueNumber(number));
    }

    [Theory]
    [InlineData("cbz", PublicationFormat.Cbz)]
    [InlineData("cbr", PublicationFormat.Cbr)]
    [InlineData("cbt", PublicationFormat.Cbt)]
    [InlineData("imageFolder", PublicationFormat.ImageFolder)]
    [InlineData("epub", PublicationFormat.Epub)]
    [InlineData("pdf", PublicationFormat.Pdf)]
    [InlineData("m4b", PublicationFormat.Audiobook)]
    [InlineData("audioFolder", PublicationFormat.Audiobook)]
    public void Each_core_format_has_its_library_format(string format, PublicationFormat expected)
    {
        Assert.Equal(expected, CoreLibrary.FormatOf(format));
    }

    [Fact]
    public void Continue_reading_lists_what_is_in_progress_most_recent_first()
    {
        var records = new[]
        {
            Issue("old", null, null, 0.3, Day),
            Issue("new", null, null, 0.6, Day.AddDays(2)),
            Issue("unread", null, null),
            Issue("done", null, null, 1, Day.AddDays(5)),
        };

        Assert.Equal(new[] { "new", "old" }, CoreLibrary.ContinueReading(records).Select(record => record.Id));
    }

    [Fact]
    public void Up_next_offers_the_next_unread_issue_of_each_started_series_most_recent_series_first()
    {
        var records = new[]
        {
            Issue("saga1", "Saga", 1, 1, Day),
            Issue("saga2", "Saga", 2),
            Issue("saga3", "Saga", 3),
            Issue("print1", "Fine Print", 1, 1, Day.AddDays(3)),
            Issue("print2", "Fine Print", 2),
            Issue("busy1", "Busy", 1, 1, Day.AddDays(4)),
            Issue("busy2", "Busy", 2, 0.5, Day.AddDays(4)),
            Issue("fresh1", "Fresh", 1),
            Issue("whole1", "Whole", 1, 1, Day.AddDays(6)),
        };

        Assert.Equal(new[] { "print2", "saga2" }, CoreLibrary.UpNext(records).Select(record => record.Id));
    }

    [Fact]
    public void Up_next_does_not_offer_a_gap_again()
    {
        var records = new[]
        {
            Issue("s1", "S", 1, 1, Day),
            Issue("s2", "S", 2),
            Issue("s3", "S", 3, 1, Day.AddDays(1)),
            Issue("s4", "S", 4),
        };

        Assert.Equal("s4", Assert.Single(CoreLibrary.UpNext(records)).Id);
    }

    [Fact]
    public void Home_shows_only_the_shelves_with_something_on_them()
    {
        Assert.True(HomeShelves.From([]).IsEmpty);

        var reading = HomeShelves.From([Issue("a", null, null, 0.4, Day)]);
        Assert.Equal(ShelfKind.ContinueReading, Assert.Single(reading.Shelves).Kind);

        var both = HomeShelves.From([Issue("a", null, null, 0.4, Day), Issue("s1", "S", 1, 1, Day), Issue("s2", "S", 2)]);
        Assert.Equal(new[] { ShelfKind.ContinueReading, ShelfKind.UpNext }, both.Shelves.Select(shelf => shelf.Kind));
    }

    [Fact]
    public void A_publication_with_no_cover_gets_the_placeholder_and_the_read_action()
    {
        var core = new CorePublication(new CoreIdentity(NormalizedPath: "/books/empty.cbz"), "cbz", "Empty", PageCount: 0);
        var record = CoreLibrary.Record(core, null, "f")!;

        var detail = PublicationDetail.Of(record, isSourceAvailable: true);

        Assert.Equal(DetailCover.Placeholder, detail.Cover);
        Assert.Equal(DetailAction.Read, detail.Action);
        Assert.Equal(DetailLocation.OnDevice, detail.Location);
        Assert.Equal(Path.GetDirectoryName("/books/empty.cbz"), detail.Folder);
    }

    [Fact]
    public void A_publication_with_progress_continues_and_one_finished_reads_again()
    {
        var core = new CorePublication(
            new CoreIdentity(NormalizedPath: "/books/saga-3.cbz"), "cbz", "Saga", Series: "Saga", Number: "3",
            Authors: ["Brian K. Vaughan"], Pencillers: ["Fiona Staples"], PageCount: 10, CoverPath: "p1.png");

        var reading = PublicationDetail.Of(CoreLibrary.Record(core, CoreProgress.Page(core.Identity, 4, 10, Day), "f")!, true);
        Assert.Equal(DetailAction.Continue, reading.Action);
        Assert.Equal(DetailCover.Wash, reading.Cover);
        Assert.Equal("Saga #3", reading.Subtitle);
        Assert.Equal(new[] { "Brian K. Vaughan", "Fiona Staples" }, reading.Credits);

        var finished = PublicationDetail.Of(CoreLibrary.Record(core, CoreProgress.Page(core.Identity, 9, 10, Day), "f")!, true);
        Assert.Equal(DetailAction.ReadAgain, finished.Action);
    }

    [Fact]
    public void A_publication_on_an_offline_source_says_so_and_cannot_be_opened()
    {
        var record = Issue("/mnt/share/a.cbz", null, null, 0.4, Day);

        var detail = PublicationDetail.Of(record, isSourceAvailable: false);

        Assert.Equal(DetailAction.Unavailable, detail.Action);
        Assert.Equal(DetailLocation.SourceOffline, detail.Location);
        Assert.Equal(0.4, detail.Progress);
    }
}
