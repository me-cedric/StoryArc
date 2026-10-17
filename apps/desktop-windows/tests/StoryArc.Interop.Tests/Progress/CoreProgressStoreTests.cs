using StoryArc.Interop.Progress;

namespace StoryArc.Interop.Tests.Progress;

/// <summary>The progress cadence over the core's own store (task 2.44, part two), end to end through the seam.</summary>
public sealed class CoreProgressStoreTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 17, 9, 30, 0, TimeSpan.Zero);

    [Fact]
    public void A_flushed_position_is_in_the_core_store_and_read_back()
    {
        using var folder = Corpus.TemporaryFolder();
        using var core = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));
        var identity = new CoreIdentity(ContentDigest: "abc", NormalizedPath: "/books/a.cbz");
        var store = new CoreProgressStore(core, id => id == "/books/a.cbz" ? new ProgressTarget(identity, 12) : null, () => Now);
        var writer = new ProgressWriter(store);

        writer.Turned("/books/a.cbz", 7, TimeSpan.Zero);
        Assert.True(writer.Flush("/books/a.cbz"));

        Assert.Equal(7, store.SavedPage(new CoreIdentity(ContentDigest: "abc")));
        var record = core.Read(identity);
        Assert.NotNull(record);
        Assert.Equal(12, record.Position.Of);
        Assert.Equal("2026-10-17T09:30:00Z", record.UpdatedAt);
    }

    [Fact]
    public void A_publication_the_store_does_not_know_is_a_named_failure_and_stays_unsaved()
    {
        using var folder = Corpus.TemporaryFolder();
        using var core = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));
        var writer = new ProgressWriter(new CoreProgressStore(core, _ => null, () => Now));

        writer.Turned("/gone.cbz", 3, TimeSpan.Zero);

        Assert.False(writer.FlushAll());
        var failure = Assert.Single(writer.Failures);
        Assert.Equal("/gone.cbz", failure.PublicationId);
        Assert.Equal(3, writer.Unsaved["/gone.cbz"]);
    }

    [Fact]
    public void Nothing_recorded_reads_as_no_saved_page()
    {
        using var folder = Corpus.TemporaryFolder();
        using var core = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));
        var store = new CoreProgressStore(core, _ => null, () => Now);

        Assert.Null(store.SavedPage(new CoreIdentity(ContentDigest: "never")));
    }
}
