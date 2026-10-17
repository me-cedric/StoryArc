using StoryArc.Interop.Shell;

namespace StoryArc.Interop.Tests.Shell;

/// <summary>
/// The command table (desktop-clients task 2.38, after 2.10): every command the spec names, its
/// shortcut, and where it is disabled. The menus are built from this table, so what passes here is
/// what the menu bar shows.
/// </summary>
public sealed class CommandTableTests
{
    [Theory]
    [InlineData("openFile", "Ctrl+O")]
    [InlineData("addSource", "Ctrl+Shift+A")]
    [InlineData("find", "Ctrl+F")]
    [InlineData("settings", "Ctrl+,")]
    [InlineData("closeWindow", "Ctrl+W")]
    [InlineData("fullScreen", "F11")]
    [InlineData("nextPage", "→")]
    [InlineData("previousPage", "←")]
    [InlineData("zoomIn", "Ctrl++")]
    [InlineData("zoomOut", "Ctrl+−")]
    [InlineData("goToPage", "Ctrl+L")]
    [InlineData("keyboardShortcuts", "Ctrl+?")]
    public void Every_command_the_spec_names_is_in_a_menu_with_its_shortcut(string id, string shortcut)
    {
        var command = CommandTable.Get(id);

        Assert.NotNull(command.Shortcut);
        Assert.Equal(shortcut, command.Shortcut?.Display);
    }

    [Fact]
    public void Quit_is_in_the_file_menu_with_no_key_of_its_own()
    {
        var quit = CommandTable.Get("quit");

        Assert.Equal(MenuName.File, quit.Menu);
        Assert.Null(quit.Shortcut);
        Assert.Null(quit.AlternateShortcut);
        Assert.Empty(CommandTable.All.Where(command => command.Shortcut == Shortcut.Control(ShortcutKey.Q)));
    }

    [Fact]
    public void Control_W_closes_the_window_in_every_kind_of_window()
    {
        var close = CommandTable.Get("closeWindow");

        Assert.Equal(Shortcut.Control(ShortcutKey.W), close.Shortcut);
        Assert.All(Enum.GetValues<WindowKind>(), window => Assert.True(CommandTable.IsEnabled(close, window)));
    }

    [Fact]
    public void Reader_commands_are_disabled_in_the_library_and_library_commands_in_a_reader()
    {
        Assert.False(CommandTable.IsEnabled(CommandTable.Get("nextPage"), WindowKind.Library));
        Assert.True(CommandTable.IsEnabled(CommandTable.Get("nextPage"), WindowKind.Reader));
        Assert.False(CommandTable.IsEnabled(CommandTable.Get("viewGrid"), WindowKind.Reader));
        Assert.True(CommandTable.IsEnabled(CommandTable.Get("viewGrid"), WindowKind.Library));
    }

    [Fact]
    public void The_menu_has_the_same_shape_in_every_window()
    {
        // A command that does not apply is disabled and not removed: the table is one list, and
        // every window reads all of it.
        foreach (var menu in Enum.GetValues<MenuName>())
        {
            Assert.NotEmpty(CommandTable.InMenu(menu));
        }

        Assert.Equal(CommandTable.All.Count, Enum.GetValues<MenuName>().Sum(menu => CommandTable.InMenu(menu).Count()));
    }

    [Theory]
    [InlineData(WindowKind.Library)]
    [InlineData(WindowKind.Reader)]
    [InlineData(WindowKind.Player)]
    public void No_two_enabled_commands_of_one_window_share_a_shortcut(WindowKind window)
    {
        var collisions = CommandTable.Collisions(window)
            .Select(collision => $"{collision.Shortcut.Display}: {collision.First.Id} and {collision.Second.Id}")
            .ToList();

        Assert.Empty(collisions);
    }

    [Fact]
    public void Command_ids_are_unique_and_name_their_resource_key()
    {
        var ids = CommandTable.All.Select(command => command.Id).ToList();

        Assert.Equal(ids.Count, ids.Distinct(StringComparer.Ordinal).Count());
        Assert.Equal("menu_openFile", CommandTable.Get("openFile").LabelKey);
    }

    [Fact]
    public void Refresh_and_find_next_carry_the_function_key_alternates()
    {
        Assert.Equal(Shortcut.Plain(ShortcutKey.F5), CommandTable.Get("refreshSources").AlternateShortcut);
        Assert.Equal(Shortcut.Plain(ShortcutKey.F3), CommandTable.Get("findNext").AlternateShortcut);
    }
}
