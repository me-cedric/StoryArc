using StoryArc.Interop.Shell;

namespace StoryArc.Interop.Tests.Shell;

/// <summary>
/// What the session file holds while windows open, move and close (desktop-clients task 2.37;
/// desktop-experience "Windows come back after a quit or a crash").
/// </summary>
public sealed class SessionRecorderTests
{
    private static readonly WindowFrame Frame = new(100, 80, 900, 1100);

    private static ReaderWindowState Reader(string id, int page = 1) => new(id, Frame, false, "laptop", page);

    private static LibraryWindowState Library() => new(new WindowFrame(0, 0, 1100, 720), false, "laptop");

    [Fact]
    public void Every_change_hands_the_new_session_text_to_the_writer()
    {
        var written = new List<string>();
        var recorder = new SessionRecorder(SessionState.Empty, written.Add);

        recorder.LibraryChanged(Library());
        recorder.ReaderChanged(Reader("saga-042", 12));

        Assert.Equal(2, written.Count);
        var restored = SessionState.Restore(written[^1]);
        Assert.Equal(Library(), restored.Library);
        Assert.Equal(Reader("saga-042", 12), Assert.Single(restored.Readers));
    }

    [Fact]
    public void A_reader_closed_by_the_reader_leaves_the_session()
    {
        var recorder = new SessionRecorder(SessionState.Empty, _ => { });
        recorder.ReaderChanged(Reader("saga-042"));
        recorder.ReaderChanged(Reader("fine-print"));

        recorder.ReaderClosed("saga-042");

        Assert.Equal(["fine-print"], recorder.State.Readers.Select(reader => reader.PublicationId));
    }

    [Fact]
    public void A_library_closed_by_the_reader_leaves_the_session_while_readers_stay()
    {
        var recorder = new SessionRecorder(SessionState.Empty, _ => { });
        recorder.LibraryChanged(Library());
        recorder.ReaderChanged(Reader("saga-042"));

        recorder.LibraryClosed();

        Assert.Null(recorder.State.Library);
        Assert.Single(recorder.State.Readers);
    }

    [Fact]
    public void Quitting_keeps_every_window_even_as_each_one_closes()
    {
        var recorder = new SessionRecorder(SessionState.Empty, _ => { });
        recorder.LibraryChanged(Library());
        recorder.ReaderChanged(Reader("saga-042", 12));
        recorder.ReaderChanged(Reader("fine-print", 3));

        recorder.Quitting();
        recorder.ReaderClosed("saga-042");
        recorder.ReaderClosed("fine-print");
        recorder.LibraryClosed();

        Assert.NotNull(recorder.State.Library);
        Assert.Equal(2, recorder.State.Readers.Count);
    }

    [Fact]
    public void Quitting_writes_the_session_once_more_and_a_close_after_it_writes_nothing()
    {
        var writes = 0;
        var recorder = new SessionRecorder(SessionState.Empty, _ => writes++);
        recorder.ReaderChanged(Reader("saga-042"));

        recorder.Quitting();
        recorder.ReaderClosed("saga-042");

        Assert.Equal(2, writes);
    }

    [Fact]
    public void A_writer_that_throws_never_stops_a_window()
    {
        var recorder = new SessionRecorder(SessionState.Empty, _ => throw new IOException("disk full"));

        recorder.ReaderChanged(Reader("saga-042", 7));

        Assert.Equal(7, Assert.Single(recorder.State.Readers).Page);
    }
}
