using StoryArc.Interop.Shell;

namespace StoryArc.Interop.Tests.Shell;

/// <summary>
/// The window model (desktop-clients task 2.37): a reader per publication, a second open focuses
/// the first, and the app quits with the last window (task 2.44).
/// </summary>
public sealed class WindowRegistryTests
{
    private sealed class FakeWindow;

    [Fact]
    public void A_second_open_of_the_same_publication_finds_the_first_window()
    {
        var registry = new WindowRegistry<FakeWindow>();
        var first = new FakeWindow();
        registry.ReaderOpened("saga-042", first);

        Assert.Same(first, registry.ReaderFor("saga-042"));
        Assert.Null(registry.ReaderFor("fine-print"));
        Assert.Throws<InvalidOperationException>(() => registry.ReaderOpened("saga-042", new FakeWindow()));
        Assert.Equal(1, registry.OpenWindowCount);
    }

    [Fact]
    public void Two_readers_are_tracked_apart_and_closing_one_leaves_the_other()
    {
        var registry = new WindowRegistry<FakeWindow>();
        registry.LibraryOpened();
        registry.ReaderOpened("saga-042", new FakeWindow());
        registry.ReaderOpened("fine-print", new FakeWindow());

        registry.ReaderClosed("saga-042");

        Assert.Equal<string>(new[] { "fine-print" }, registry.OpenPublications);
        Assert.Equal(2, registry.OpenWindowCount);
    }

    [Fact]
    public void The_app_quits_once_when_the_last_window_closes_and_not_before()
    {
        var registry = new WindowRegistry<FakeWindow>();
        var quits = 0;
        registry.LastWindowClosed += () => quits++;
        registry.LibraryOpened();
        registry.ReaderOpened("saga-042", new FakeWindow());

        registry.LibraryClosed();
        Assert.Equal(0, quits);

        registry.ReaderClosed("saga-042");
        Assert.Equal(1, quits);
    }

    [Fact]
    public void Closing_a_reader_that_was_never_opened_changes_nothing()
    {
        var registry = new WindowRegistry<FakeWindow>();
        var quits = 0;
        registry.LastWindowClosed += () => quits++;
        registry.LibraryOpened();

        registry.ReaderClosed("unknown");

        Assert.Equal(0, quits);
        Assert.True(registry.IsLibraryOpen);
    }
}
