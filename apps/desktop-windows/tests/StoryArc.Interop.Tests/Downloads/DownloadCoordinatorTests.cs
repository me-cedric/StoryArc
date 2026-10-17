using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Downloads;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Tests.Downloads;

/// <summary>
/// The download rules of desktop-clients task 3.23, one test each: a metered connection, an unmetered one, a connection that changes
/// mid-download, no connection, the quit prompt and the resume at the next launch, the retry bound, and a transfer that lands. The
/// rules themselves run in the core across the seam; the transfer is a fake, so a test stops it where it wants without a network.
/// </summary>
public sealed class DownloadCoordinatorTests
{
    [Fact]
    public void A_metered_connection_holds_back_what_the_policy_queued_and_says_why_but_a_reader_can_still_start_one_by_hand()
    {
        using var run = new Run(ConnectionState.Metered);
        run.Coordinator.Start();

        run.Coordinator.Add("queued", "Queued", "https://x/queued.cbz", null, null, byHand: false);
        run.Coordinator.Add("hand", "By hand", "https://x/hand.cbz", null, null, byHand: true);

        var held = run.Coordinator.Queue.Get("queued")!;
        Assert.Equal(DownloadStatus.Paused, held.Status);
        Assert.Equal("waitingForUnmetered", held.Pause);
        run.Eventually(() => run.Transfer.Started.Contains("hand"), "the download the reader asked for starts");
        Assert.DoesNotContain("queued", run.Transfer.Started);
        run.Transfer.Release("hand");
        run.Idle();
    }

    [Fact]
    public void An_unmetered_connection_runs_the_policys_bound_and_the_next_row_starts_as_one_lands()
    {
        using var run = new Run(ConnectionState.Unmetered);
        run.Coordinator.Start();

        foreach (var id in new[] { "a", "b", "c", "d", "e" })
        {
            run.Coordinator.Add(id, id, "https://x/" + id, null, null, byHand: false);
        }

        run.Eventually(() => run.Transfer.Started.Count == 3, "three run at once");
        Assert.Equal(3, run.Coordinator.Active.Count);
        run.Transfer.Release("a");
        run.Eventually(() => run.Transfer.Started.Count == 4, "a fourth starts when one lands");
        foreach (var id in new[] { "b", "c", "d", "e" })
        {
            run.Transfer.Release(id);
        }

        run.Eventually(() => run.Coordinator.Queue.Rows.All(row => row.Status == DownloadStatus.Finished), "every row finishes");
        Assert.Equal(5, run.Landed.Count);
    }

    [Fact]
    public void A_connection_that_turns_metered_mid_download_pauses_the_row_keeps_its_bytes_and_an_unmetered_one_resumes_it()
    {
        using var run = new Run(ConnectionState.Unmetered);
        run.Transfer.On("a", Step.ReportThenBlock(100, 1000));
        run.Coordinator.Start();
        run.Coordinator.Add("a", "A", "https://x/a.cbz", null, 1000, byHand: false);
        run.Eventually(() => run.Transfer.Started.Count == 1 && run.Coordinator.ProgressOf("a") is not null, "the transfer is under way");

        run.Connection = ConnectionState.Metered;
        run.Coordinator.NetworkChanged();
        run.Idle();

        var paused = run.Coordinator.Queue.Get("a")!;
        Assert.Equal(DownloadStatus.Paused, paused.Status);
        Assert.Equal("waitingForUnmetered", paused.Pause);
        Assert.Equal(100, paused.DownloadedBytes);
        Assert.Empty(run.Coordinator.Active);

        run.Transfer.On("a", Step.Land(1000, Resumption.Resumed, from: 100));
        run.Connection = ConnectionState.Unmetered;
        run.Coordinator.NetworkChanged();
        run.Eventually(() => run.Coordinator.Queue.Get("a")!.Status == DownloadStatus.Finished, "it resumes and lands");

        Assert.Equal(Resumption.Resumed, run.Coordinator.LastAttemptOf("a"));
        Assert.Equal(2, run.Transfer.Started.Count);
        Assert.Equal(new[] { "a" }, run.Landed);
    }

    [Fact]
    public void With_no_connection_the_queue_waits_in_grey_and_starts_nothing_until_one_returns()
    {
        using var run = new Run(ConnectionState.Offline);
        run.Coordinator.Start();

        run.Coordinator.Add("a", "A", "https://x/a.cbz", null, null, byHand: true);

        var waiting = run.Coordinator.Queue.Get("a")!;
        Assert.Equal(DownloadStatus.Paused, waiting.Status);
        Assert.Equal("waitingForNetwork", waiting.Pause);
        Assert.Empty(run.Transfer.Started);

        // A row the fake has no script for blocks until the test releases it, so this one is scripted to land the moment it starts.
        run.Transfer.On("a", Step.Land(1000, Resumption.Fresh));
        run.Connection = ConnectionState.Unmetered;
        run.Coordinator.NetworkChanged();
        run.Eventually(() => run.Coordinator.Queue.Get("a")!.Status == DownloadStatus.Finished, "it runs when a connection returns");

        Assert.Equal(new[] { "a" }, run.Transfer.Started);
        run.Eventually(() => run.Landed.Count == 1, "it reports the landing");
    }

    [Fact]
    public async Task Quitting_during_a_download_asks_first_stops_it_keeps_the_partial_file_and_the_next_launch_resumes_it()
    {
        var saved = string.Empty;
        using var first = new Run(ConnectionState.Unmetered, text => saved = text);
        first.Transfer.On("a", Step.ReportThenBlock(400, 1000));
        first.Coordinator.Start();
        first.Coordinator.Add("a", "A", "https://x/a.cbz", null, 1000, byHand: false);
        first.Eventually(() => first.Coordinator.ProgressOf("a") is not null, "the transfer is under way");
        Assert.True(first.Coordinator.NeedsQuitPrompt, "the app says before quitting that the download will pause and resume");

        await first.Coordinator.QuitAsync();

        Assert.False(first.Coordinator.NeedsQuitPrompt);
        Assert.Empty(first.Coordinator.Active);
        var kept = first.Coordinator.Queue.Get("a")!;
        Assert.Equal(DownloadStatus.Queued, kept.Status);
        Assert.Equal(400, kept.DownloadedBytes);
        Assert.Contains("400", saved, StringComparison.Ordinal);

        using var second = new Run(ConnectionState.Unmetered, queue: DownloadQueue.Restore(saved));
        second.Transfer.On("a", Step.Land(1000, Resumption.Resumed, from: 400));
        second.Coordinator.Start();

        second.Eventually(() => second.Coordinator.Queue.Get("a")!.Status == DownloadStatus.Finished, "the next launch resumes it");
        Assert.Equal(Resumption.Resumed, second.Coordinator.LastAttemptOf("a"));
    }

    [Fact]
    public void A_transfer_that_fails_is_tried_again_after_two_and_four_seconds_and_then_fails_for_good()
    {
        using var run = new Run(ConnectionState.Unmetered);
        run.Transfer.On("a", Step.Fail(StoryArcStatus.Unreachable), Step.Fail(StoryArcStatus.Unreachable), Step.Fail(StoryArcStatus.Unreachable));
        run.Coordinator.Start();

        run.Coordinator.Add("a", "A", "https://x/a.cbz", null, null, byHand: false);

        run.Eventually(() => run.Coordinator.Queue.Get("a")!.Status == DownloadStatus.Failed && run.Transfer.Started.Count == 3, "three attempts");
        var row = run.Coordinator.Queue.Get("a")!;
        Assert.Equal("network", row.FailureKind);
        Assert.Equal(3, row.Attempts);
        Assert.Equal(3, run.Coordinator.AttemptsOf("a"));
        Assert.Equal(new[] { TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(4) }, run.Delays);

        // The reader's retry forgets what was spent and tries once more.
        run.Transfer.On("a", Step.Land(10, Resumption.Fresh));
        run.Coordinator.Resume("a");
        run.Eventually(() => run.Coordinator.Queue.Get("a")!.Status == DownloadStatus.Finished, "the reader's retry lands");
        Assert.Equal(0, run.Coordinator.AttemptsOf("a"));
    }

    [Fact]
    public void A_failure_that_succeeds_on_the_second_try_lands_and_the_backoff_matches_the_cores_own()
    {
        using var run = new Run(ConnectionState.Unmetered);
        run.Transfer.On("a", Step.Fail(StoryArcStatus.Unreachable), Step.Land(10, Resumption.Fresh));
        run.Coordinator.Start();

        run.Coordinator.Add("a", "A", "https://x/a.cbz", null, null, byHand: false);

        run.Eventually(() => run.Coordinator.Queue.Get("a")!.Status == DownloadStatus.Finished, "the second try lands");
        Assert.Equal(new[] { TimeSpan.FromSeconds(2) }, run.Delays);
        foreach (var attempts in new[] { 1, 2 })
        {
            var failing = DownloadQueues.Apply(
                DownloadQueue.Empty,
                [QueueOp.Queue("x", "X", "r"), .. Enumerable.Repeat(QueueOp.Fail("x", QueueFailure.Network, retryable: true), attempts)]);
            Assert.Equal((int)DownloadBackoff.After(attempts).TotalSeconds, Assert.Single(failing.Retry).Seconds);
        }
    }

    [Fact]
    public void Bytes_that_will_not_open_are_requeued_once_and_a_format_the_app_does_not_read_fails_at_once()
    {
        using var run = new Run(ConnectionState.Unmetered);
        run.Transfer.On("bad", Step.Fail(StoryArcStatus.Unreadable), Step.Fail(StoryArcStatus.Unreadable));
        run.Transfer.On("seven", Step.Fail(StoryArcStatus.Unsupported, "CB7 is not supported"));
        run.Transfer.On("full", Step.Fail(StoryArcStatus.Storage, "the disk is full"));
        run.Transfer.On("locked", Step.Fail(StoryArcStatus.Unauthorized));
        run.Coordinator.Start();

        foreach (var id in new[] { "bad", "seven", "full", "locked" })
        {
            run.Coordinator.Add(id, id, "https://x/" + id, null, null, byHand: false);
        }

        run.Eventually(() => run.Coordinator.Queue.Rows.All(row => row.Status == DownloadStatus.Failed), "each ends failed");
        Assert.Equal(2, run.Transfer.StartsOf("bad"));
        Assert.Equal("unreadable", run.Coordinator.Queue.Get("bad")!.FailureKind);
        Assert.Equal(1, run.Transfer.StartsOf("seven"));
        Assert.Equal("unsupported", run.Coordinator.Queue.Get("seven")!.FailureKind);
        Assert.Equal("disk", run.Coordinator.Queue.Get("full")!.FailureKind);
        Assert.Equal("401", run.Coordinator.Queue.Get("locked")!.FailureDetail);
        Assert.Empty(run.Delays);
    }

    [Fact]
    public void A_reader_pauses_resumes_and_removes_a_download_and_each_stops_or_starts_its_transfer()
    {
        using var run = new Run(ConnectionState.Unmetered);
        run.Transfer.On("a", Step.ReportThenBlock(10, 100));
        run.Coordinator.Start();
        run.Coordinator.Add("a", "A", "https://x/a.cbz", null, 100, byHand: false);
        run.Eventually(() => run.Coordinator.ProgressOf("a") is not null, "under way");

        run.Coordinator.Pause("a");
        run.Idle();
        var paused = run.Coordinator.Queue.Get("a")!;
        Assert.Equal("byReader", paused.Pause);
        Assert.Empty(run.Coordinator.Active);

        run.Transfer.On("a", Step.ReportThenBlock(50, 100));
        run.Coordinator.Resume("a");
        run.Eventually(() => run.Transfer.StartsOf("a") == 2 && run.Coordinator.ProgressOf("a") is { Received: 50 }, "resumed");

        run.Coordinator.Remove("a");
        run.Idle();
        Assert.Null(run.Coordinator.Queue.Get("a"));
        Assert.Null(run.Coordinator.ProgressOf("a"));
    }

    [Fact]
    public void The_timer_writes_a_transfers_bytes_into_the_queue_and_saves_it_so_a_kill_loses_a_moment_not_a_download()
    {
        var saved = string.Empty;
        using var run = new Run(ConnectionState.Unmetered, text => saved = text);
        run.Transfer.On("a", Step.ReportThenBlock(250, 1000));
        run.Coordinator.Start();
        run.Coordinator.Add("a", "A", "https://x/a.cbz", null, 1000, byHand: false);
        run.Eventually(() => run.Coordinator.ProgressOf("a") is not null, "under way");

        run.Coordinator.Tick();

        Assert.Equal(250, run.Coordinator.Queue.Get("a")!.DownloadedBytes);
        Assert.Equal(0.25, run.Coordinator.Queue.Get("a")!.Fraction);
        Assert.Contains("250", saved, StringComparison.Ordinal);
        run.Transfer.Release("a");
        run.Idle();
    }

    /// <summary>One coordinator over a fake transfer, an environment a test sets by hand, and a way to wait for a thread.</summary>
    private sealed class Run : IDisposable
    {
        private readonly List<TimeSpan> _delays = [];
        private readonly List<string> _landed = [];

        public Run(ConnectionState connection, Action<string>? save = null, DownloadQueue? queue = null)
        {
            Connection = connection;
            Transfer = new FakeTransfer();
            Coordinator = new DownloadCoordinator(
                Transfer,
                queue ?? DownloadQueue.Empty,
                new DownloadEnvironment(
                    () => Connection,
                    () => new DownloadPolicySettings(),
                    () => 0,
                    () => DateTimeOffset.UnixEpoch,
                    text => save?.Invoke(text),
                    (wait, cancel) =>
                    {
                        lock (_delays)
                        {
                            _delays.Add(wait);
                        }

                        return Task.CompletedTask;
                    }));
            Coordinator.Landed += (row, landing) =>
            {
                lock (_landed)
                {
                    _landed.Add(row.Id);
                }
            };
        }

        public ConnectionState Connection { get; set; }

        public FakeTransfer Transfer { get; }

        public DownloadCoordinator Coordinator { get; }

        public IReadOnlyList<TimeSpan> Delays
        {
            get
            {
                lock (_delays)
                {
                    return [.. _delays];
                }
            }
        }

        public IReadOnlyList<string> Landed
        {
            get
            {
                lock (_landed)
                {
                    return [.. _landed];
                }
            }
        }

        public void Eventually(Func<bool> condition, string what)
        {
            Assert.True(SpinWait.SpinUntil(condition, TimeSpan.FromSeconds(15)), "timed out waiting for: " + what);
        }

        public void Idle() => Coordinator.WhenIdleAsync().WaitAsync(TimeSpan.FromSeconds(15)).GetAwaiter().GetResult();

        public void Dispose()
        {
            Transfer.ReleaseAll();
            Coordinator.QuitAsync().GetAwaiter().GetResult();
            Coordinator.Dispose();
        }
    }
}

/// <summary>A scripted step of a fake transfer.</summary>
internal sealed record Step(Func<DownloadRow, IProgress<DownloadProgress>, CancelToken, FakeTransfer, DownloadLanding> Act)
{
    /// <summary>Lands at once, saying how it began.</summary>
    public static Step Land(long length, Resumption how, ulong from = 0) =>
        new((row, progress, cancel, fake) => new DownloadLanding("C:/downloads/" + row.Id + ".cbz", how, from, length, null));

    public static Step Fail(StoryArcStatus status, string? message = null) =>
        new((row, progress, cancel, fake) => throw new StoryArcException("storyarc_download_fetch", status, message ?? status.ToString()));

    /// <summary>Reports some bytes, then waits for the test to release it or for the cancel token, which keeps the partial file.</summary>
    public static Step ReportThenBlock(ulong received, long total) => new((row, progress, cancel, fake) =>
    {
        progress.Report(new DownloadProgress(received, total));
        fake.Block(row.Id, cancel);
        return new DownloadLanding("C:/downloads/" + row.Id + ".cbz", Resumption.Fresh, 0, total, null);
    });
}

/// <summary>Stands in for the network: each row runs the steps a test scripted for it, and a row with none lands at once after waiting to be released.</summary>
internal sealed class FakeTransfer : IDownloadTransfer
{
    private readonly Lock _gate = new();
    private readonly Dictionary<string, Queue<Step>> _scripts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _starts = new(StringComparer.Ordinal);
    private readonly List<string> _started = [];
    private readonly HashSet<string> _released = new(StringComparer.Ordinal);
    private bool _all;

    public IReadOnlyList<string> Started
    {
        get
        {
            lock (_gate)
            {
                return [.. _started];
            }
        }
    }

    public int StartsOf(string id)
    {
        lock (_gate)
        {
            return _starts.GetValueOrDefault(id);
        }
    }

    public void On(string id, params Step[] steps)
    {
        lock (_gate)
        {
            _scripts[id] = new Queue<Step>(steps);
        }
    }

    public void Release(string id)
    {
        lock (_gate)
        {
            _ = _released.Add(id);
        }
    }

    public void ReleaseAll()
    {
        lock (_gate)
        {
            _all = true;
        }
    }

    /// <summary>Waits until <paramref name="id"/> is released or the token is raised; a raised token ends the transfer as the core does.</summary>
    public void Block(string id, CancelToken cancel)
    {
        while (true)
        {
            lock (_gate)
            {
                if (_all || _released.Contains(id))
                {
                    return;
                }
            }

            if (cancel.IsCancelled)
            {
                throw new StoryArcException("storyarc_download_fetch", StoryArcStatus.Cancelled, "the download was cancelled");
            }

            Thread.Sleep(5);
        }
    }

    public DownloadLanding Fetch(DownloadRow row, IProgress<DownloadProgress> progress, CancelToken cancel)
    {
        Step step;
        lock (_gate)
        {
            _started.Add(row.Id);
            _starts[row.Id] = _starts.GetValueOrDefault(row.Id) + 1;
            step = _scripts.TryGetValue(row.Id, out var script) && script.Count > 0
                ? script.Dequeue()
                : Step.ReportThenBlock(0, 100);
        }

        return step.Act(row, progress, cancel, this);
    }
}
