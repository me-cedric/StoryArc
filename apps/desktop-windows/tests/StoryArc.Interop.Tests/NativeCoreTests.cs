using System.Text.RegularExpressions;
using StoryArc.Interop;

namespace StoryArc.Interop.Tests;

/// <summary>
/// The seam, test first (desktop-clients task 1.8). Each test names one rule of the C ABI in
/// <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>, so a change to the Rust side that
/// breaks the rule fails here by name. The raw calls go through <c>NativeMethods</c>, the file
/// csbindgen generates from the Rust source; the wrappers in <c>NativeCore</c> sit on top.
/// </summary>
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

    [Fact]
    public unsafe void A_buffer_round_trips_through_the_core_and_is_freed_once()
    {
        byte[] bytes = [0x53, 0x74, 0x6F, 0x72, 0x79, 0x00, 0xFF, 0x41, 0x72, 0x63];

        // The raw seam: bytes in, a Rust-owned StoryArcBuffer out, freed exactly once.
        StoryArcBuffer buffer = default;
        int status;
        fixed (byte* data = bytes)
        {
            status = NativeMethods.storyarc_buffer_roundtrip(data, (nuint)bytes.Length, &buffer);
        }

        Assert.Equal((int)StoryArcStatus.Ok, status);
        Assert.False(buffer.data is null, "storyarc_buffer_roundtrip wrote no data pointer");
        Assert.Equal((nuint)bytes.Length, buffer.len);
        Assert.True(buffer.capacity >= buffer.len, "a buffer's capacity is never below its length");
        Assert.Equal(bytes, new ReadOnlySpan<byte>(buffer.data, bytes.Length).ToArray());
        NativeMethods.storyarc_buffer_free(buffer);

        // A zeroed struct is safe to free: the rule that lets a wrapper free on every path.
        NativeMethods.storyarc_buffer_free(default);

        // The wrapper does the same trip and hands back a managed copy.
        Assert.Equal(bytes, NativeCore.RoundTrip(bytes));
        Assert.Empty(NativeCore.RoundTrip(ReadOnlySpan<byte>.Empty));
    }

    [Fact]
    public unsafe void A_failing_call_leaves_a_message_for_its_own_thread_only()
    {
        // Each sequence runs on a thread of its own, because the message belongs to the thread
        // that made the failing call, and nothing another test did may be read as this one's.
        string? beforeFailure = null;
        int status = -1;
        string? afterFailure = null;
        var failing = new Thread(() =>
        {
            beforeFailure = NativeCore.LastError();
            status = NativeMethods.storyarc_buffer_roundtrip(null, 0, null);
            afterFailure = NativeCore.LastError();
        });
        failing.Start();
        failing.Join();

        string? onAFreshThread = "unread";
        var fresh = new Thread(() => onAFreshThread = NativeCore.LastError());
        fresh.Start();
        fresh.Join();

        Assert.Null(beforeFailure);
        Assert.Equal((int)StoryArcStatus.InvalidArgument, status);
        Assert.False(string.IsNullOrWhiteSpace(afterFailure), "storyarc_last_error returned no message after a failing call");
        Assert.Null(onAFreshThread);
    }

    [Fact]
    public void A_cancel_token_raises_once_and_stays_raised()
    {
        var token = new CancelToken();

        Assert.False(token.IsInvalid);
        Assert.False(token.IsCancelled);

        token.Cancel();
        Assert.True(token.IsCancelled);

        token.Cancel();
        Assert.True(token.IsCancelled, "raising a token twice must change nothing");

        token.Dispose();
        Assert.True(token.IsClosed);
    }
}
