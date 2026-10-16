using StoryArc.Interop.Shell;

namespace StoryArc.Interop.Tests.Shell;

/// <summary>The commands that are wired in task 2.38: close, quit, settings and full screen.</summary>
public sealed class CommandRoutingTests
{
    [Theory]
    [InlineData(WindowKind.Library)]
    [InlineData(WindowKind.Reader)]
    public void Close_window_and_quit_are_answered_in_every_window_and_quit_has_no_key(WindowKind window)
    {
        Assert.True(CommandRouting.IsHandled("closeWindow", window));
        Assert.True(CommandRouting.IsHandled("quit", window));
        Assert.Null(CommandTable.Get("quit").Shortcut);
        Assert.Null(CommandTable.Get("quit").AlternateShortcut);
        Assert.Equal("Ctrl+W", CommandTable.Get("closeWindow").Shortcut?.Display);
    }

    [Fact]
    public void Full_screen_is_answered_in_a_reader_only()
    {
        Assert.True(CommandRouting.IsHandled("fullScreen", WindowKind.Reader));
        Assert.False(CommandRouting.IsHandled("fullScreen", WindowKind.Library));
    }

    [Fact]
    public void A_command_nothing_answers_yet_is_not_handled()
    {
        Assert.False(CommandRouting.IsHandled("nextPage", WindowKind.Reader));
    }

    [Fact]
    public void Every_handled_command_is_in_the_table_and_applies_in_its_window()
    {
        foreach (var window in new[] { WindowKind.Library, WindowKind.Reader })
        {
            foreach (var command in CommandTable.All.Where(command => CommandRouting.IsHandled(command.Id, window)))
            {
                Assert.True(CommandTable.IsEnabled(command, window), $"{command.Id} in {window}");
            }
        }
    }
}
