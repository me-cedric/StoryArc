using StoryArc.Interop;

namespace StoryArc.Interop.Tests;

/// <summary>
/// The wave 2 seam through the C# wrappers, against the shared corpus in <c>packages/test-fixtures</c>
/// (desktop-clients tasks 2.1 and 2.40). Each test exercises one export the way the Windows app calls
/// it, and the expectations are the corpus manifest's, so a disagreement with the Rust suite or the
/// phones fails here by name.
/// </summary>
public sealed class NativeCoreSeamTests
{
    [Fact]
    public void Every_status_the_header_defines_has_its_name_here()
    {
        Assert.Equal(NativeMethods.STORYARC_OK, (int)StoryArcStatus.Ok);
        Assert.Equal(NativeMethods.STORYARC_ERROR_INVALID_ARGUMENT, (int)StoryArcStatus.InvalidArgument);
        Assert.Equal(NativeMethods.STORYARC_ERROR_CANCELLED, (int)StoryArcStatus.Cancelled);
        Assert.Equal(NativeMethods.STORYARC_ERROR_NOT_FOUND, (int)StoryArcStatus.NotFound);
        Assert.Equal(NativeMethods.STORYARC_ERROR_UNSUPPORTED, (int)StoryArcStatus.Unsupported);
        Assert.Equal(NativeMethods.STORYARC_ERROR_UNREADABLE, (int)StoryArcStatus.Unreadable);
        Assert.Equal(NativeMethods.STORYARC_ERROR_STORAGE, (int)StoryArcStatus.Storage);
        Assert.Equal(NativeMethods.STORYARC_ERROR_INTERNAL, (int)StoryArcStatus.Internal);
        Assert.Equal(NativeMethods.STORYARC_ERROR_UNREACHABLE, (int)StoryArcStatus.Unreachable);
        Assert.Equal(NativeMethods.STORYARC_ERROR_UNAUTHORIZED, (int)StoryArcStatus.Unauthorized);
    }

    [Fact]
    public void A_folder_lists_its_publications_as_records()
    {
        using var folder = Corpus.TemporaryFolder();
        folder.Copy("comics/large-page.cbz");
        folder.Copy("comics/natural-sort.cbz");
        folder.Copy("comics/manga-metadata.cbz");

        using var source = ComicFolder.Open(folder.FullPath);
        var records = source.Records();

        Assert.Equal(3, records.Count);
        Assert.All(records, record => Assert.Equal("cbz", record.Format));
        Assert.All(records, record => Assert.False(string.IsNullOrEmpty(record.Identity.ContentDigest)));
        var natural = Assert.Single(records, record => record.DisplayTitle == "natural-sort");
        Assert.Equal(12, natural.PageCount);
        var manga = Assert.Single(records, record => record.Series == "Fixture Manga");
        Assert.True(manga.IsRightToLeft);
        Assert.NotNull(manga.AddedAt);
    }

    [Fact]
    public void A_refused_or_locked_file_is_left_out_of_the_folder_and_the_rest_still_lists()
    {
        using var folder = Corpus.TemporaryFolder();
        folder.Copy("comics/single-page.cbz");
        folder.Copy("comics/refused.cb7");
        folder.Copy("comics/password-protected.cbz");

        using var source = ComicFolder.Open(folder.FullPath);

        var record = Assert.Single(source.Records());
        Assert.Equal("single-page", record.DisplayTitle);
    }

    [Fact]
    public void A_folder_that_is_not_there_is_not_found_and_named()
    {
        var missing = Path.Combine(Path.GetTempPath(), "storyarc-no-such-folder-" + Guid.NewGuid().ToString("N"));

        var error = Assert.Throws<StoryArcException>(() => ComicFolder.Open(missing));

        Assert.Equal(StoryArcStatus.NotFound, error.Status);
        Assert.Equal("storyarc_folder_open", error.Call);
        Assert.Contains("storyarc-no-such-folder-", error.CoreMessage);
    }

    [Fact]
    public void A_raised_cancel_token_stops_the_scan_and_hands_back_nothing()
    {
        using var token = new CancelToken();
        token.Cancel();

        var error = Assert.Throws<StoryArcException>(() => ComicFolder.Open(Corpus.Path("comics"), token));

        Assert.Equal(StoryArcStatus.Cancelled, error.Status);
        Assert.False(token.IsClosed, "the scan releases its hold on the token, it does not free it");
    }

    [Fact]
    public void A_publication_answers_its_page_count_and_metadata_as_the_manifest_says()
    {
        using var publication = ComicPublication.Open(Corpus.Path("comics/manga-metadata.cbz"));

        Assert.Equal(4, publication.PageCount);
        var metadata = publication.Metadata();
        Assert.Equal("Fixture Manga", metadata.Series);
        Assert.Equal("3", metadata.Number);
        Assert.Equal(2L, metadata.Volume);
        Assert.Equal(new[] { "First Writer", "Second Writer" }, metadata.Authors);
        Assert.Equal("Fixture Press", metadata.Publisher);
        Assert.Equal(2026L, metadata.Year);
        Assert.True(metadata.IsRightToLeft);
        Assert.Equal(4, metadata.PageCount);
    }

    [Fact]
    public void A_page_decodes_to_rgba_at_the_size_asked_and_at_its_own_size()
    {
        using var publication = ComicPublication.Open(Corpus.Path("comics/large-page.cbz"));

        var bounded = publication.DecodePage(0, maxPixelSize: 600);
        Assert.Equal((400, 600), (bounded.Width, bounded.Height));
        Assert.Equal(400 * 600 * 4, bounded.Rgba.Length);
        var centre = ((300 * 400) + 200) * 4;
        int[] expected = [185, 199, 243, 255];
        for (var channel = 0; channel < 4; channel++)
        {
            Assert.InRange(bounded.Rgba[centre + channel], expected[channel] - 1, expected[channel] + 1);
        }

        var full = publication.DecodePage(0);
        Assert.Equal((2000, 3000), (full.Width, full.Height));
    }

    [Fact]
    public void A_page_in_a_codec_the_build_refuses_names_the_codec_and_an_index_past_the_end_is_refused()
    {
        using var publication = ComicPublication.Open(Corpus.Path("comics/unsupported-codec.cbz"));

        var codec = Assert.Throws<StoryArcException>(() => publication.DecodePage(1));
        Assert.Equal(StoryArcStatus.Unsupported, codec.Status);
        Assert.Contains("JPEG XL", codec.CoreMessage);

        var past = Assert.Throws<StoryArcException>(() => publication.DecodePage(9));
        Assert.Equal(StoryArcStatus.InvalidArgument, past.Status);

        // The page before it still decodes: one bad page never closes the book.
        Assert.True(publication.DecodePage(0, 64).Width > 0);
    }

    [Fact]
    public void A_CB7_archive_is_refused_by_name()
    {
        var error = Assert.Throws<StoryArcException>(() => ComicPublication.Open(Corpus.Path("comics/refused.cb7")));

        Assert.Equal(StoryArcStatus.Unsupported, error.Status);
        Assert.Contains("CB7", error.CoreMessage);
    }

    [Fact]
    public void A_password_protected_archive_is_unreadable()
    {
        var error = Assert.Throws<StoryArcException>(() => ComicPublication.Open(Corpus.Path("comics/password-protected.cbz")));

        Assert.Equal(StoryArcStatus.Unreadable, error.Status);
    }

    [Theory]
    [InlineData("comics/rar4-store.cbr", 3)]
    [InlineData("comics/tar-store.cbt", 3)]
    [InlineData("comics/double-page-spread.cbz", 3)]
    [InlineData("comics/single-page.cbz", 1)]
    public void Each_container_opens_with_the_manifest_page_count(string file, int pages)
    {
        if (file.EndsWith(".cbr", StringComparison.Ordinal) && OperatingSystem.IsWindows())
        {
            // RAR on Windows waits for libarchive's MSVC header (design.md, Decision 5).
            return;
        }

        using var publication = ComicPublication.Open(Corpus.Path(file));

        Assert.Equal(pages, publication.PageCount);
    }

    [Fact]
    public void A_handle_used_after_dispose_throws_instead_of_reaching_the_core()
    {
        var publication = ComicPublication.Open(Corpus.Path("comics/single-page.cbz"));
        publication.Dispose();
        publication.Dispose();

        Assert.True(publication.IsClosed);
        Assert.Throws<ObjectDisposedException>(() => publication.PageCount);
    }

    [Fact]
    public void A_progress_record_is_written_and_read_back_by_its_digest()
    {
        using var folder = Corpus.TemporaryFolder();
        using var store = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));
        var identity = new CoreIdentity(ContentDigest: "d1", NormalizedPath: "/a.cbz");

        Assert.Null(store.Read(identity));

        var at = new DateTimeOffset(2025, 12, 30, 13, 6, 40, TimeSpan.Zero);
        store.Write(CoreProgress.Page(identity, 12, 40, at));

        var back = store.Read(new CoreIdentity(ContentDigest: "d1"));
        Assert.NotNull(back);
        Assert.Equal(new CorePosition("page", 12, 40), back.Position);
        Assert.Equal("2025-12-30T13:06:40Z", back.UpdatedAt);
        Assert.False(back.IsFinished);
    }

    [Fact]
    public void A_record_that_is_not_one_is_refused_and_the_store_keeps_working()
    {
        using var folder = Corpus.TemporaryFolder();
        using var store = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));

        var error = Assert.Throws<StoryArcException>(() => store.WriteJson("{not json"));

        Assert.Equal(StoryArcStatus.InvalidArgument, error.Status);
        Assert.Equal("null", store.ReadJson("""{"contentDigest":"none"}"""));
    }

    [Fact]
    public void The_last_page_finishes_the_publication_and_finished_reads_as_whole()
    {
        var identity = new CoreIdentity(ContentDigest: "d2");
        var now = DateTimeOffset.UnixEpoch;

        Assert.False(CoreProgress.Page(identity, 0, 3, now).IsFinished);
        Assert.Equal(0.5, CoreProgress.Page(identity, 1, 3, now).Fraction);
        var last = CoreProgress.Page(identity, 2, 3, now);
        Assert.True(last.IsFinished);
        Assert.Equal(1.0, last.Fraction);
        Assert.DoesNotContain("fraction", last.ToJson(), StringComparison.Ordinal);
    }
}
