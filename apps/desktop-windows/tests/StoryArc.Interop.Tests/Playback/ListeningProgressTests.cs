using StoryArc.Interop.Playback;

namespace StoryArc.Interop.Tests.Playback;

/// <summary>A narrated book's place in the core's store, in the phones' listening shape (ADR-0006).</summary>
public sealed class ListeningProgressTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 18, 9, 0, 0, TimeSpan.Zero);
    private static readonly CoreIdentity Book = new(ContentDigest: "dune", NormalizedPath: "/books/Dune.m4b");

    [Fact]
    public void A_place_is_saved_and_read_back_as_the_phones_write_it()
    {
        using var folder = Corpus.TemporaryFolder();
        using var store = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));

        ListeningProgress.Write(store, Book, TimeSpan.FromSeconds(61.5), TimeSpan.FromMinutes(10), Now);

        var record = store.Read(new CoreIdentity(ContentDigest: "dune"));
        Assert.NotNull(record);
        Assert.Equal("listening", record.Position.Kind);
        Assert.Equal(0, record.Position.Part);
        Assert.Equal(1, record.Position.PartCount);
        Assert.Equal(61_500L, record.Position.OffsetMillis);
        Assert.Equal(600_000L, record.Position.OfMillis);
        Assert.False(record.IsFinished);
        Assert.Equal(TimeSpan.FromSeconds(61.5), ListeningProgress.Saved(store, Book));
    }

    [Fact]
    public void A_later_place_on_this_desktop_replaces_the_earlier_one_even_when_it_is_further_back()
    {
        // A local save replaces, as on the phones: going back to hear a chapter again is a place. The furthest-wins
        // merge belongs to sync, between devices.
        using var folder = Corpus.TemporaryFolder();
        using var store = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));

        ListeningProgress.Write(store, Book, TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(10), Now);
        ListeningProgress.Write(store, Book, TimeSpan.FromMinutes(2), TimeSpan.FromMinutes(10), Now.AddMinutes(1));

        Assert.Equal(TimeSpan.FromMinutes(2), ListeningProgress.Saved(store, Book));
    }

    [Fact]
    public void A_finished_book_and_an_unknown_one_resume_from_the_start()
    {
        using var folder = Corpus.TemporaryFolder();
        using var store = ProgressStore.Open(Path.Combine(folder.FullPath, "library.sqlite"));

        Assert.Null(ListeningProgress.Saved(store, Book));
        ListeningProgress.Write(store, Book, TimeSpan.FromMinutes(10), TimeSpan.FromMinutes(10), Now);
        Assert.Null(ListeningProgress.Saved(store, Book));
    }

    [Fact]
    public void A_page_record_is_unchanged_by_the_new_fields()
    {
        var page = CoreProgress.Page(Book, 3, 12, Now);
        var json = page.ToJson();

        Assert.Contains("\"kind\":\"page\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("offsetMillis", json, StringComparison.Ordinal);
        Assert.DoesNotContain("part", json, StringComparison.Ordinal);
    }
}
