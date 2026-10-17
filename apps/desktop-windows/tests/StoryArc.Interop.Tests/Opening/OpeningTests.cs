using System.Xml.Linq;
using StoryArc.Interop.Opening;

namespace StoryArc.Interop.Tests.Opening;

/// <summary>
/// Opening files (task 2.42): what a drop, the command line or a file activation opens, what it
/// refuses by name (a CB7 archive among them), the window limit, the command line as Windows splits
/// it, and the recent list behind the Jump List.
/// </summary>
public sealed class OpeningTests
{
    // Forward slashes: Windows reads them as separators and so does every other host, so the names
    // OpenRefusal takes with Path.GetFileName are the same on the Linux and macOS runners.
    private static readonly HashSet<string> Files = new(StringComparer.OrdinalIgnoreCase)
    {
        "C:/Comics/Saga 1.cbz", "C:/Comics/Saga 2.cbr", "C:/Comics/Old.cb7", "C:/Comics/notes.txt", "C:/Comics/Strip.cbt",
    };

    private static readonly HashSet<string> Folders = new(StringComparer.OrdinalIgnoreCase) { "C:/Comics/Manga" };

    private static OpenPlan Plan(IEnumerable<string> paths, int limit = OpenRequest.WindowLimit) =>
        OpenRequest.Plan(paths, Files.Contains, Folders.Contains, limit);

    [Fact]
    public void Supported_files_open_and_the_rest_are_refused_by_name_while_the_others_still_open()
    {
        var plan = Plan(["C:/Comics/Saga 1.cbz", "C:/Comics/Old.cb7", "C:/Comics/notes.txt", "C:/Comics/Saga 2.cbr"]);

        Assert.Equal(new[] { "C:/Comics/Saga 1.cbz", "C:/Comics/Saga 2.cbr" }, plan.Open);
        Assert.Equal(new[] { RefusalReason.Cb7, RefusalReason.NotAFormat }, plan.Refused.Select(refusal => refusal.Reason));
        Assert.Equal("Old.cb7", plan.Refused[0].Name);
    }

    [Fact]
    public void A_file_that_cannot_be_reached_is_named_and_nothing_else_opens_for_it()
    {
        var plan = Plan(["E:/Unplugged/Gone.cbz"]);

        Assert.Empty(plan.Open);
        var refusal = Assert.Single(plan.Refused);
        Assert.Equal(RefusalReason.NotFound, refusal.Reason);
        Assert.Equal("Gone.cbz", refusal.Name);
    }

    [Fact]
    public void Several_files_open_up_to_the_limit_and_the_rest_are_listed()
    {
        var plan = Plan(["C:/Comics/Saga 1.cbz", "C:/Comics/Saga 2.cbr", "C:/Comics/Strip.cbt"], limit: 2);

        Assert.Equal(2, plan.Open.Count);
        Assert.Equal(new[] { "C:/Comics/Strip.cbt" }, plan.Overflow);
    }

    [Fact]
    public void A_dropped_folder_is_offered_as_a_library_and_not_opened()
    {
        var plan = Plan(["C:/Comics/Manga"]);

        Assert.Equal(new[] { "C:/Comics/Manga" }, plan.Folders);
        Assert.Empty(plan.Open);
        Assert.Empty(plan.Refused);
    }

    [Fact]
    public void The_same_file_twice_opens_once_and_an_empty_request_is_empty()
    {
        Assert.Single(Plan(["C:/Comics/Saga 1.cbz", "c:/comics/saga 1.CBZ"]).Open);
        Assert.True(Plan(["", "  "]).IsEmpty);
    }

    [Fact]
    public void The_package_claims_only_what_the_core_opens_page_by_page_and_never_cb7()
    {
        var manifest = XDocument.Load(Path.Combine(AppContext.BaseDirectory, "Package.appxmanifest"));
        XNamespace uap = "http://schemas.microsoft.com/appx/manifest/uap/windows10";

        var association = Assert.Single(manifest.Descendants(uap + "FileTypeAssociation"));
        var claimed = association.Descendants(uap + "FileType").Select(type => type.Value.Trim()).ToList();

        Assert.Equal(new[] { ".cbz", ".cbr", ".cbt" }, OpenRequest.Associated);
        Assert.Equal(OpenRequest.Associated, claimed);
        Assert.DoesNotContain(".cb7", OpenRequest.Readable);
        Assert.Equal("storyarc.comicarchive", association.Attribute("Name")?.Value);
    }

    [Theory]
    [InlineData(@"StoryArc.exe C:\a.cbz", new[] { "StoryArc.exe", @"C:\a.cbz" })]
    [InlineData(@"StoryArc.exe ""C:\My Comics\a b.cbz"" C:\c.cbr", new[] { "StoryArc.exe", @"C:\My Comics\a b.cbz", @"C:\c.cbr" })]
    [InlineData(@"""C:\Program Files\StoryArc.exe""  ""C:\dir\\""", new[] { @"C:\Program Files\StoryArc.exe", @"C:\dir\" })]
    [InlineData(@"a\\\""b ""c d""e", new[] { @"a\""b", "c de" })]
    [InlineData(@"""""", new[] { "" })]
    [InlineData("   ", new string[0])]
    public void The_command_line_splits_as_windows_splits_it(string commandLine, string[] expected)
    {
        Assert.Equal(expected, LaunchArguments.Split(commandLine));
    }

    [Fact]
    public void The_paths_skip_the_executable_and_the_options()
    {
        var paths = LaunchArguments.Paths(["StoryArc.exe", "--restore", @"C:\a.cbz", @"D:\b.cbr"], skipExecutable: true);

        Assert.Equal(new[] { @"C:\a.cbz", @"D:\b.cbr" }, paths);
    }

    [Theory]
    [InlineData(@"""C:\Program Files\WindowsApps\StoryArc\StoryArc.exe"" ""C:\a b.cbz""", new[] { @"C:\a b.cbz" })]
    [InlineData(@"""C:\a b.cbz"" D:\c.cbr", new[] { @"C:\a b.cbz", @"D:\c.cbr" })]
    [InlineData("", new string[0])]
    public void A_launch_argument_string_gives_its_paths_with_or_without_the_executable(string commandLine, string[] expected)
    {
        Assert.Equal(expected, LaunchArguments.PathsIn(commandLine));
    }

    [Theory]
    [InlineData(@"C:\Comics\Saga 1.cbz")]
    [InlineData(@"C:\dir with space\")]
    [InlineData(@"C:\odd""name.cbz")]
    public void A_quoted_path_splits_back_whole(string path)
    {
        Assert.Equal(new[] { path }, LaunchArguments.Split(LaunchArguments.Quote(path)));
    }

    [Fact]
    public void The_recent_list_is_newest_first_one_entry_per_file_and_capped()
    {
        var at = new DateTimeOffset(2026, 10, 17, 0, 0, 0, TimeSpan.Zero);
        var recent = RecentItems.Empty;
        for (var index = 0; index < RecentItems.Limit + 3; index++)
        {
            recent = recent.Opened($@"C:\c\{index}.cbz", $"Issue {index}", at.AddMinutes(index));
        }

        recent = recent.Opened(@"C:\c\5.cbz", "Issue 5", at.AddHours(1));

        Assert.Equal(RecentItems.Limit, recent.Items.Count);
        Assert.Equal(@"C:\c\5.cbz", recent.Items[0].Path);
        Assert.Single(recent.Items, item => item.Path == @"C:\c\5.cbz");
        Assert.Equal(@"C:\c\12.cbz", recent.Items[1].Path);
    }

    [Fact]
    public void A_recent_file_that_is_gone_drops_out_without_an_error()
    {
        var recent = RecentItems.Empty
            .Opened(@"C:\a.cbz", "A", DateTimeOffset.UnixEpoch)
            .Opened(@"C:\gone.cbz", "Gone", DateTimeOffset.UnixEpoch);

        var pruned = recent.Pruned(path => path != @"C:\gone.cbz");

        Assert.Equal("A", Assert.Single(pruned.Items).Title);
        Assert.Same(pruned, pruned.Pruned(_ => true));
    }

    [Fact]
    public void The_recent_list_survives_a_save_and_a_damaged_file_is_an_empty_list()
    {
        var recent = RecentItems.Empty.Opened(@"C:\a.cbz", "A", new DateTimeOffset(2026, 1, 2, 3, 4, 5, TimeSpan.Zero));

        var restored = RecentItems.Restore(recent.Save());

        Assert.Equal(recent.Items, restored.Items);
        Assert.Empty(RecentItems.Restore("{broken").Items);
        Assert.Empty(RecentItems.Restore(null).Items);
    }

    [Fact]
    public void The_audio_extensions_open_in_the_player_and_are_all_readable()
    {
        Assert.Equal(new[] { ".flac", ".m4a", ".m4b", ".mp3", ".ogg" }, OpenRequest.Audio.Order(StringComparer.Ordinal));
        Assert.All(OpenRequest.Audio, extension => Assert.Contains(extension, OpenRequest.Readable));
        Assert.DoesNotContain(".epub", OpenRequest.Audio);
    }
}
