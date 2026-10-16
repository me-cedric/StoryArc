using System.Text.RegularExpressions;
using StoryArc.Interop;

namespace StoryArc.Interop.Tests;

/// <summary>
/// The seam, test first (desktop-clients task 1.8). Each test names one rule of the C ABI from
/// design.md Decision 5, so a change to the Rust side that breaks the rule fails here by name.
/// The tests fail to link until task 1.8a generates <c>NativeMethods.g.cs</c>.
/// </summary>
public sealed partial class NativeCoreTests
{
    /// <summary>A token no operation can hold: the core never hands this value out.</summary>
    private const ulong NobodysToken = ulong.MaxValue;

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

    [Fact]
    public void Cancel_of_a_token_nobody_holds_is_refused_with_a_code()
    {
        Assert.Equal(StoryArcStatus.UnknownToken, NativeCore.Cancel(NobodysToken));
    }

    [Fact]
    public void A_failed_call_leaves_a_message_that_round_trips_through_the_buffer_free()
    {
        // The message belongs to the thread that made the failing call, so the sequence runs on a
        // thread of its own: nothing another test did can be read as this thread's last error.
        string? before = null;
        string? after = null;
        var status = StoryArcStatus.Ok;
        var thread = new Thread(() =>
        {
            before = NativeCore.LastError();
            status = NativeCore.Cancel(NobodysToken);
            after = NativeCore.LastError();
        });
        thread.Start();
        thread.Join();

        Assert.Null(before);
        Assert.Equal(StoryArcStatus.UnknownToken, status);
        Assert.False(string.IsNullOrWhiteSpace(after), "storyarc_last_error returned no message after a failed cancel");
    }

    [Fact]
    public unsafe void Freeing_no_buffer_is_a_no_op()
    {
        // The rule that lets a wrapper free whatever storyarc_last_error returned without a null check.
        NativeMethods.storyarc_buffer_free(null, 0);
    }
}
