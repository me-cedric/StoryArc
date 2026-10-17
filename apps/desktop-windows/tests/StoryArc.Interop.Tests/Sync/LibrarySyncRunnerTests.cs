using System.Diagnostics;
using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;
using StoryArc.Interop.Sync;

namespace StoryArc.Interop.Tests.Sync;

/// <summary>The sync rules of desktop-clients task 3.23: at start without blocking, at quit within five seconds and only when the position changed, and grey when the folder is away.</summary>
public sealed class LibrarySyncRunnerTests
{
    private static readonly LibraryMerge Empty = new("{}", 0, [], [], []);

    [Fact]
    public async Task At_start_the_sync_runs_on_a_worker_and_a_slow_location_never_holds_the_caller()
    {
        using var slow = new ManualResetEventSlim();
        var applied = 0;
        var runner = new LibrarySyncRunner(() => true, () => "{}", _ =>
        {
            slow.Wait(TimeSpan.FromSeconds(30));
            return Empty;
        }, _ => Interlocked.Increment(ref applied));

        var task = runner.AtStartAsync();

        Assert.False(task.IsCompleted, "the call returned at once with the sync still running");
        Assert.Equal(SyncState.Syncing, runner.State);
        slow.Set();
        var outcome = await task.WaitAsync(TimeSpan.FromSeconds(30));
        Assert.Equal(SyncResult.Synced, outcome.Result);
        Assert.Equal(SyncState.Synced, runner.State);
        Assert.Equal(1, applied);
    }

    [Fact]
    public async Task Two_asks_while_one_runs_are_one_sync()
    {
        using var slow = new ManualResetEventSlim();
        var calls = 0;
        var runner = new LibrarySyncRunner(() => true, () => "{}", _ =>
        {
            Interlocked.Increment(ref calls);
            slow.Wait(TimeSpan.FromSeconds(30));
            return Empty;
        }, _ => { });

        var first = runner.AtStartAsync();
        var second = runner.AtStartAsync();
        slow.Set();
        await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(30));

        Assert.Same(first, second);
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task At_quit_an_unchanged_position_writes_nothing()
    {
        var calls = 0;
        var runner = new LibrarySyncRunner(() => true, () => "{}", _ =>
        {
            Interlocked.Increment(ref calls);
            return Empty;
        }, _ => { });

        var outcome = await runner.AtQuitAsync();

        Assert.Equal(SyncResult.Skipped, outcome.Result);
        Assert.Equal(0, calls);
    }

    [Fact]
    public async Task At_quit_a_changed_position_is_written_once_and_the_next_quit_has_nothing_to_write()
    {
        var calls = 0;
        var runner = new LibrarySyncRunner(() => true, () => "{}", _ =>
        {
            Interlocked.Increment(ref calls);
            return Empty;
        }, _ => { });
        runner.PositionChanged();

        var first = await runner.AtQuitAsync();
        var second = await runner.AtQuitAsync();

        Assert.Equal(SyncResult.Synced, first.Result);
        Assert.Equal(SyncResult.Skipped, second.Result);
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task At_quit_a_location_slower_than_the_budget_is_left_behind_and_the_app_quits_regardless()
    {
        using var slow = new ManualResetEventSlim();
        var runner = new LibrarySyncRunner(() => true, () => "{}", _ =>
        {
            slow.Wait(TimeSpan.FromSeconds(30));
            return Empty;
        }, _ => { });
        runner.PositionChanged();
        var waited = Stopwatch.StartNew();

        var outcome = await runner.AtQuitAsync(TimeSpan.FromMilliseconds(200));

        Assert.Equal(SyncResult.TimedOut, outcome.Result);
        Assert.True(waited.Elapsed < TimeSpan.FromSeconds(5), "the quit did not wait for the slow location");
        Assert.Equal(TimeSpan.FromSeconds(5), LibrarySyncRunner.QuitBudget);
        slow.Set();
        // The sync the quit left behind finishes on its own; wait for it so the event is not disposed under it.
        Assert.Equal(SyncResult.Synced, (await runner.AtStartAsync().WaitAsync(TimeSpan.FromSeconds(30))).Result);
    }

    [Fact]
    public async Task A_folder_that_does_not_answer_is_grey_not_an_error_and_is_tried_again_after_a_minute()
    {
        var now = TimeSpan.Zero;
        var answers = new Queue<Func<LibraryMerge>>(
        [
            () => throw new StoryArcException("storyarc_library_sync", StoryArcStatus.Unreachable, "/nas/sync is not there"),
            () => Empty,
        ]);
        var runner = new LibrarySyncRunner(() => true, () => "{}", _ => answers.Dequeue()(), _ => { }, () => now);

        var first = await runner.AtStartAsync();

        Assert.Equal(SyncResult.Unreachable, first.Result);
        Assert.Equal(SyncState.Unreachable, runner.State);
        Assert.Equal("/nas/sync is not there", runner.LastMessage);
        now = TimeSpan.FromSeconds(30);
        Assert.Null(runner.RetryIfDue());
        now = TimeSpan.FromSeconds(61);
        var retry = runner.RetryIfDue();
        Assert.NotNull(retry);
        Assert.Equal(SyncResult.Synced, (await retry).Result);
        Assert.Equal(SyncState.Synced, runner.State);
        Assert.Null(runner.RetryIfDue());
    }

    [Fact]
    public async Task A_document_from_a_newer_app_is_named_and_left_alone()
    {
        var runner = new LibrarySyncRunner(
            () => true,
            () => "{}",
            _ => throw new StoryArcException("storyarc_library_sync", StoryArcStatus.Unsupported, "this document is format 9"),
            _ => { });

        var outcome = await runner.AtStartAsync();

        Assert.Equal(SyncResult.Refused, outcome.Result);
        Assert.Equal(SyncState.DocumentTooNew, runner.State);
        Assert.Contains("format 9", outcome.Message, StringComparison.Ordinal);
        Assert.Null(runner.RetryIfDue());
    }

    [Fact]
    public async Task With_no_sync_folder_chosen_nothing_is_asked()
    {
        var runner = new LibrarySyncRunner(() => false, () => "{}", _ => throw new InvalidOperationException("not called"), _ => { });
        runner.PositionChanged();

        Assert.Equal(SyncResult.Skipped, (await runner.AtStartAsync()).Result);
        Assert.Equal(SyncState.NoFolder, runner.State);
        Assert.Equal(SyncResult.Skipped, (await runner.AtQuitAsync()).Result);
    }

    [Fact]
    public async Task Against_the_core_a_folder_syncs_and_an_unplugged_one_is_unreachable()
    {
        using var folder = Corpus.TemporaryFolder();
        var target = folder.FullPath;
        var runner = new LibrarySyncRunner(
            () => true,
            () => LibrarySnapshots.Build([], new PinBook(), ShelvesState.Empty, []),
            snapshot => LibraryDocuments.Sync(target, "windows", "1.0.0", DateTimeOffset.UnixEpoch, snapshot),
            _ => { });

        var synced = await runner.AtStartAsync();
        Assert.Equal(SyncResult.Synced, synced.Result);
        Assert.True(File.Exists(Path.Combine(target, "StoryArc Library.json")));

        target = Path.Combine(folder.FullPath, "unplugged");
        var unplugged = await runner.AtStartAsync();
        Assert.Equal(SyncResult.Unreachable, unplugged.Result);
        Assert.Equal(SyncState.Unreachable, runner.State);
    }
}
