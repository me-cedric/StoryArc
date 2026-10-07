using System.Text.RegularExpressions;
using StoryArc.Interop;

namespace StoryArc.Interop.Tests;

public sealed partial class NativeCoreTests
{
    [GeneratedRegex(@"\[workspace\.package\][^\[]*?^version\s*=\s*""([^""]+)""", RegexOptions.Multiline | RegexOptions.Singleline)]
    private static partial Regex WorkspaceVersion();

    [Fact]
    public void Version_matches_the_rust_workspace_manifest()
    {
        var manifest = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "workspace.Cargo.toml"));
        var match = WorkspaceVersion().Match(manifest);

        Assert.True(match.Success, "no version under [workspace.package] in Cargo.toml");
        Assert.Equal(match.Groups[1].Value, NativeCore.Version());
    }
}
