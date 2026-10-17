using System.Xml.Linq;
using StoryArc.Interop.Library;
using StoryArc.Interop.Opening;
using StoryArc.Interop.Sources;
using StoryArc.Interop.Tests.Library;

namespace StoryArc.Interop.Tests.Opening;

/// <summary>
/// The <c>storyarc://</c> link (task 5.8; desktop-experience "Opening a link or a command"): a plain open
/// opens the publication, an unknown title is named and changes nothing, and a link carrying a command is
/// refused or reduced to its name, so nothing runs.
/// </summary>
public sealed class StoryArcLinkTests
{
    private static readonly LibraryRecord[] Records =
    [
        LibraryViewModelTests.Record("C:/Comics/Saga 1.cbz", "Saga 1"),
        LibraryViewModelTests.Record("C:/Comics/Strip.cbt", "Strip"),
    ];

    private static readonly FolderSource[] Sources = [new("comics", "C:/Comics", "Comics")];

    private static LinkAction Resolve(string link) => StoryArcLink.Resolve(link, Records, Sources);

    [Fact]
    public void A_plain_link_to_a_title_the_library_holds_opens_it()
    {
        var action = Resolve("storyarc://publication/Saga%201");

        Assert.Equal(LinkOutcome.OpenPublication, action.Outcome);
        Assert.Equal("C:/Comics/Saga 1.cbz", action.Id);
    }

    [Fact]
    public void A_link_to_a_source_shows_the_sources()
    {
        var action = Resolve("storyarc://source/Comics");

        Assert.Equal(LinkOutcome.ShowSource, action.Outcome);
        Assert.Equal("comics", action.Id);
    }

    [Theory]
    [InlineData("storyarc://publication/Nothing%20Like%20It")]
    [InlineData("storyarc://source/Elsewhere")]
    public void An_unknown_title_or_source_is_named_and_nothing_opens(string link)
    {
        var action = Resolve(link);

        Assert.Equal(LinkOutcome.NotFound, action.Outcome);
        Assert.Null(action.Id);
        Assert.False(string.IsNullOrEmpty(action.Name));
    }

    [Theory]
    [InlineData("storyarc://settings/reset")]
    [InlineData("storyarc://clear-history")]
    [InlineData("storyarc://publication")]
    [InlineData("storyarc://publication/Saga%201/delete")]
    [InlineData("storyarc://run/cmd.exe")]
    [InlineData("storyarc:")]
    [InlineData("https://publication/Saga%201")]
    public void A_link_carrying_a_command_or_naming_nothing_is_refused(string link)
    {
        var action = Resolve(link);

        Assert.Equal(LinkOutcome.Refused, action.Outcome);
        Assert.Null(action.Id);
    }

    [Fact]
    public void A_query_after_a_name_is_ignored_and_only_the_name_opens()
    {
        var action = Resolve("storyarc://publication/Strip?delete=all&exec=calc#now");

        Assert.Equal(LinkOutcome.OpenPublication, action.Outcome);
        Assert.Equal("C:/Comics/Strip.cbt", action.Id);
    }

    [Theory]
    [InlineData("storyarc://publication/Saga%201", true)]
    [InlineData("STORYARC://x", true)]
    [InlineData("C:/Comics/Saga 1.cbz", false)]
    [InlineData("--new-window", false)]
    public void A_link_is_told_from_a_path(string argument, bool isLink) =>
        Assert.Equal(isLink, StoryArcLink.IsLink(argument));

    [Fact]
    public void A_link_on_the_command_line_is_a_link_and_never_a_path()
    {
        var arguments = new[] { "storyarc.exe", "storyarc://publication/Strip", "C:/Comics/Saga 1.cbz" };

        Assert.Equal(new[] { "C:/Comics/Saga 1.cbz" }, LaunchArguments.Paths(arguments, skipExecutable: true));
        Assert.Equal(new[] { "storyarc://publication/Strip" }, LaunchArguments.Links(arguments, skipExecutable: true));
        Assert.Equal(new[] { "storyarc://source/Comics" }, LaunchArguments.LinksIn("\"storyarc://source/Comics\""));
        Assert.Empty(LaunchArguments.PathsIn("storyarc://source/Comics"));
    }

    [Fact]
    public void The_package_registers_the_scheme_the_parser_reads()
    {
        var manifest = XDocument.Load(Path.Combine(AppContext.BaseDirectory, "Package.appxmanifest"));
        XNamespace uap = "http://schemas.microsoft.com/appx/manifest/uap/windows10";

        var protocol = Assert.Single(manifest.Descendants(uap + "Protocol"));

        Assert.Equal(StoryArcLink.Scheme, protocol.Attribute("Name")?.Value);
    }
}
