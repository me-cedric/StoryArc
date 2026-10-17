using StoryArc.Interop.Shell;

namespace StoryArc.Interop.Tests.Shell;

/// <summary>
/// The window-state record, test first (desktop-clients task 2.37). Each test names one scenario of
/// desktop-experience "Windows come back after a quit or a crash" or "The window model".
/// </summary>
public sealed class WindowStateTests
{
    private static readonly DisplayBounds Laptop = new("laptop", 0, 0, 1920, 1080);
    private static readonly DisplayBounds External = new("external", 1920, 0, 2560, 1440);

    private static SessionState TwoReaders() => new(
        new LibraryWindowState(new WindowFrame(100, 80, 1100, 720), false, "laptop"),
        [
            new ReaderWindowState("saga-042", new WindowFrame(2000, 40, 900, 1100), false, "external", 12),
            new ReaderWindowState("fine-print", new WindowFrame(300, 200, 800, 900), true, "laptop", 3),
        ]);

    [Fact]
    public void Save_then_restore_round_trips_the_library_and_every_reader()
    {
        var session = TwoReaders();

        var restored = SessionState.Restore(session.Save());

        Assert.Equal(session.Library, restored.Library);
        Assert.Equal(session.Readers, restored.Readers);
    }

    [Fact]
    public void Restore_reads_nothing_an_empty_file_or_a_damaged_file_as_the_empty_session()
    {
        Assert.Equal(SessionState.Empty, SessionState.Restore(null));
        Assert.Equal(SessionState.Empty, SessionState.Restore(""));
        Assert.Equal(SessionState.Empty, SessionState.Restore("{ not json"));
        Assert.Null(SessionState.Restore("null").Library);
        Assert.Empty(SessionState.Restore("null").Readers);
    }

    [Fact]
    public void Restore_ignores_keys_a_later_version_may_add()
    {
        var text = """{"library":null,"readers":[],"futureKey":1}""";

        var restored = SessionState.Restore(text);

        Assert.Null(restored.Library);
        Assert.Empty(restored.Readers);
    }

    [Fact]
    public void A_frame_inside_a_connected_display_is_kept()
    {
        var frame = new WindowFrame(2000, 40, 900, 1100);

        var fitted = frame.FitTo([Laptop, External], "external", WindowDefaults.MinWidth, WindowDefaults.MinHeight);

        Assert.Equal(frame, fitted);
    }

    [Fact]
    public void A_frame_on_a_display_that_is_gone_opens_fully_visible_on_one_that_exists()
    {
        var frame = new WindowFrame(2000, 40, 900, 1100);

        var fitted = frame.FitTo([Laptop], "external", WindowDefaults.MinWidth, WindowDefaults.MinHeight);

        Assert.True(fitted.IsInside(Laptop), $"{fitted} is not inside the laptop display");
        Assert.Equal(900, fitted.Width);
        Assert.Equal(1080, fitted.Height);
    }

    [Fact]
    public void A_frame_larger_than_every_display_shrinks_to_the_display_and_never_below_the_minimum()
    {
        var huge = new WindowFrame(-50, -50, 5000, 4000);
        var tiny = new WindowFrame(10, 10, 100, 100);

        var fittedHuge = huge.FitTo([Laptop], null, WindowDefaults.MinWidth, WindowDefaults.MinHeight);
        var fittedTiny = tiny.FitTo([Laptop], null, WindowDefaults.MinWidth, WindowDefaults.MinHeight);

        Assert.Equal(new WindowFrame(0, 0, 1920, 1080), fittedHuge);
        Assert.Equal(new WindowFrame(10, 10, WindowDefaults.MinWidth, WindowDefaults.MinHeight), fittedTiny);
    }

    [Fact]
    public void With_no_display_known_the_size_is_clamped_and_the_position_kept()
    {
        var frame = new WindowFrame(40, 40, 100, 100);

        var fitted = frame.FitTo([], "laptop", WindowDefaults.MinWidth, WindowDefaults.MinHeight);

        Assert.Equal(new WindowFrame(40, 40, WindowDefaults.MinWidth, WindowDefaults.MinHeight), fitted);
    }

    [Fact]
    public void A_restoration_reopens_what_it_can_and_names_what_it_cannot()
    {
        var plan = RestorationPlan.From(TwoReaders(), publicationId => publicationId != "fine-print");

        var reopened = Assert.Single(plan.Reopen);
        Assert.Equal("saga-042", reopened.PublicationId);
        Assert.Equal(12, reopened.Page);
        Assert.Equal<string>(new[] { "fine-print" }, plan.Skipped);
    }

    [Fact]
    public void With_reader_replaces_a_reader_of_the_same_publication_and_without_reader_drops_it()
    {
        var session = TwoReaders();

        var moved = session.WithReader(new ReaderWindowState("saga-042", new WindowFrame(0, 0, 900, 1100), false, "laptop", 13));
        var closed = moved.WithoutReader("fine-print");

        Assert.Equal(2, moved.Readers.Count);
        Assert.Equal(13, moved.Readers.Single(reader => reader.PublicationId == "saga-042").Page);
        var left = Assert.Single(closed.Readers);
        Assert.Equal("saga-042", left.PublicationId);
    }
}
