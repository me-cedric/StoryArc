using StoryArc.Interop.Progress;

namespace StoryArc.Interop.Tests.Progress;

/// <summary>
/// Closing and quitting (desktop-clients task 2.44, after 2.17): the five-second cadence, the
/// flush before a close and a quit, and a store that fails.
/// </summary>
public sealed class ProgressWriterTests
{
    private sealed class RecordingStore : IProgressStore
    {
        public List<(string PublicationId, int Page)> Writes { get; } = [];

        public bool Fails { get; set; }

        public void Write(string publicationId, int page)
        {
            if (Fails)
            {
                throw new IOException("There is not enough space on the disk.");
            }

            Writes.Add((publicationId, page));
        }
    }

    private static TimeSpan Seconds(double seconds) => TimeSpan.FromSeconds(seconds);

    [Fact]
    public void A_turn_is_written_no_later_than_five_seconds_after_it_and_not_before()
    {
        var store = new RecordingStore();
        var writer = new ProgressWriter(store);

        writer.Turned("saga-042", 12, Seconds(0));

        Assert.Equal(Seconds(5), writer.DueAt);
        Assert.False(writer.Tick(Seconds(4.9)));
        Assert.Empty(store.Writes);
        Assert.True(writer.Tick(Seconds(5)));
        Assert.Equal<(string, int)>([("saga-042", 12)], store.Writes);
        Assert.Null(writer.DueAt);
        Assert.Empty(writer.Unsaved);
    }

    [Fact]
    public void A_burst_of_turns_writes_once_with_the_last_page_never_once_per_frame()
    {
        var store = new RecordingStore();
        var writer = new ProgressWriter(store);

        for (var frame = 0; frame < 300; frame++)
        {
            writer.Turned("saga-042", frame, Seconds(frame / 60.0));
        }

        Assert.False(writer.Tick(Seconds(4.99)));
        Assert.True(writer.Tick(Seconds(5)));
        var write = Assert.Single(store.Writes);
        Assert.Equal(("saga-042", 299), write);
    }

    [Fact]
    public void Closing_a_reader_window_writes_its_position_at_once()
    {
        var store = new RecordingStore();
        var writer = new ProgressWriter(store);
        writer.Turned("saga-042", 12, Seconds(0));
        writer.Turned("fine-print", 3, Seconds(1));

        Assert.True(writer.Flush("saga-042"));

        Assert.Equal<(string, int)>([("saga-042", 12)], store.Writes);
        Assert.Equal(3, writer.Unsaved["fine-print"]);
        Assert.NotNull(writer.DueAt);
    }

    [Fact]
    public void Quitting_writes_every_open_readers_position_before_the_process_ends()
    {
        var store = new RecordingStore();
        var writer = new ProgressWriter(store);
        writer.Turned("saga-042", 12, Seconds(0));
        writer.Turned("fine-print", 3, Seconds(1));

        Assert.True(writer.FlushAll());

        Assert.Equal(2, store.Writes.Count);
        Assert.Empty(writer.Unsaved);
        Assert.Null(writer.DueAt);
    }

    [Fact]
    public void A_write_that_fails_keeps_the_position_names_the_failure_and_never_throws()
    {
        var store = new RecordingStore { Fails = true };
        var writer = new ProgressWriter(store);
        writer.Turned("saga-042", 12, Seconds(0));

        var written = writer.Flush("saga-042");

        Assert.False(written);
        Assert.Equal(12, writer.Unsaved["saga-042"]);
        var failure = Assert.Single(writer.Failures);
        Assert.Equal("saga-042", failure.PublicationId);
        Assert.Equal(12, failure.Page);
        Assert.Contains("space", failure.Reason);

        store.Fails = false;
        Assert.True(writer.FlushAll());
        Assert.Equal<(string, int)>([("saga-042", 12)], store.Writes);
        Assert.Empty(writer.Unsaved);
    }

    [Fact]
    public void Flushing_a_publication_with_nothing_pending_is_true_and_writes_nothing()
    {
        var store = new RecordingStore();
        var writer = new ProgressWriter(store);

        Assert.True(writer.Flush("never-opened"));
        Assert.True(writer.FlushAll());
        Assert.Empty(store.Writes);
    }
}
