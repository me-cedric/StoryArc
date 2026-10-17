using System.Collections.Concurrent;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Downloads;

/// <summary>
/// What the coordinator needs of the transfer, so a test can stand in for the network. A transfer blocks on the calling thread
/// until the file lands or fails, reports its progress, and honours <paramref name="cancel"/> by throwing
/// <see cref="StoryArcException"/> with <see cref="StoryArcStatus.Cancelled"/> while keeping the partial file.
/// </summary>
public interface IDownloadTransfer
{
    DownloadLanding Fetch(DownloadRow row, IProgress<DownloadProgress> progress, CancelToken cancel);
}

/// <summary>What the coordinator reads of the app and writes back to it: the settings it follows, the clock, the file, the wait.</summary>
public sealed record DownloadEnvironment(
    Func<ConnectionState> Connection,
    Func<DownloadPolicySettings> Policy,
    Func<long> UsedBytes,
    Func<DateTimeOffset> Now,
    Action<string> SaveQueue,
    Func<TimeSpan, CancellationToken, Task> Delay);

/// <summary>The wait before a failed transfer is tried again: three attempts, doubling from two seconds. The core states the same bound.</summary>
public static class DownloadBackoff
{
    /// <summary>Attempts the queue spends before a failure is final (storyarc-core <c>DownloadQueue::ATTEMPT_LIMIT</c>).</summary>
    public const int AttemptLimit = 3;

    /// <summary>The wait after the <paramref name="attempts"/>th failure: 2, 4 seconds, then none.</summary>
    public static TimeSpan After(int attempts) => TimeSpan.FromSeconds(2L << Math.Clamp(attempts - 1, 0, 16));
}

/// <summary>
/// Runs the download queue (desktop-clients task 3.23; offline-downloads; desktop-experience, "Metered connections" and "No
/// presence when the app is closed"). The core owns the rules: <see cref="DownloadQueues"/> says what the policy holds back, what may
/// start and what a failure costs. This class owns the transfers, which the seam cannot mark in the queue (<c>marking</c> is not
/// exported), so a row in flight stays queued in the core's value and the coordinator knows it is active.
///
/// What it promises: a metered connection holds back what the reader did not ask for by hand, and the queue says why in grey; a
/// connection that changes mid-download pauses the rows the policy now holds back and stops their transfers, keeping the partial
/// files; an unmetered connection releases them; with no connection the queue waits; a failed transfer is tried again after two and
/// four seconds and then fails for good; bytes that arrive whole and will not open are queued once more; a quit stops every transfer,
/// keeps the partial files, leaves the rows queued, and the next launch resumes each from where it stopped. A download that lands
/// raises <see cref="Landed"/>, and nothing here posts a notification.
/// </summary>
public sealed class DownloadCoordinator : IDisposable
{
    private readonly IDownloadTransfer _transfer;
    private readonly DownloadEnvironment _environment;
    private readonly Lock _gate = new();
    private readonly Dictionary<string, Flight> _flights = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, DownloadProgress> _progress = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _attempts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Resumption> _lastAttempt = new(StringComparer.Ordinal);
    private readonly CancellationTokenSource _disposed = new();
    private DownloadQueue _queue;

    public DownloadCoordinator(IDownloadTransfer transfer, DownloadQueue queue, DownloadEnvironment environment)
    {
        _transfer = transfer;
        _queue = queue;
        _environment = environment;
    }

    /// <summary>Raised, on whichever thread made the change, after the queue or a transfer's state moved: the screen redraws.</summary>
    public event Action? Changed;

    /// <summary>Raised when a download landed, verified, with the row it was and where the file is.</summary>
    public event Action<DownloadRow, DownloadLanding>? Landed;

    public DownloadQueue Queue
    {
        get
        {
            lock (_gate)
            {
                return _queue;
            }
        }
    }

    /// <summary>The ids being transferred now.</summary>
    public IReadOnlyCollection<string> Active
    {
        get
        {
            lock (_gate)
            {
                return [.. _flights.Keys];
            }
        }
    }

    /// <summary>Whether quitting would stop a transfer: the app then says before it quits that the download pauses and resumes at the next launch.</summary>
    public bool NeedsQuitPrompt => Active.Count > 0;

    /// <summary>The bytes a transfer has received so far and its total, or <c>null</c> when none is reporting.</summary>
    public DownloadProgress? ProgressOf(string id) => _progress.TryGetValue(id, out var progress) ? progress : null;

    /// <summary>Failures spent on a row since it was last started by the reader: three and the failure is final.</summary>
    public int AttemptsOf(string id)
    {
        lock (_gate)
        {
            return _attempts.GetValueOrDefault(id);
        }
    }

    /// <summary>How the last transfer of a row began, which the row says: fresh, resumed from a kept partial file, or restarted.</summary>
    public Resumption? LastAttemptOf(string id)
    {
        lock (_gate)
        {
            return _lastAttempt.TryGetValue(id, out var how) ? how : null;
        }
    }

    /// <summary>
    /// At launch: the queue as the last run left it (a row in flight is queued again, with its bytes), then the connection and the policy
    /// applied, then whatever may start does. A reader who quit mid-download finds it resumed.
    /// </summary>
    public void Start()
    {
        Apply([], reclaim: true);
        Pump();
    }

    /// <summary>
    /// Adds a publication the reader asked to keep. <paramref name="byHand"/> overrides "Wi-Fi only" once: a download the reader started
    /// runs on a metered connection, one the policy queued does not.
    /// </summary>
    public void Add(string id, string title, string remote, string? sourceId, long? expectedBytes, bool byHand)
    {
        Apply([QueueOp.Queue(id, title, remote, sourceId, expectedBytes, byHand), QueueOp.Hold(_environment.Connection(), _environment.Policy(), _environment.UsedBytes())]);
        Pump();
    }

    public void Pause(string id)
    {
        Apply([QueueOp.Pause(id)]);
        Cancel(id);
    }

    /// <summary>A paused or failed row goes back in the queue with the failures it spent forgotten: a retry the reader asked for.</summary>
    public void Resume(string id)
    {
        lock (_gate)
        {
            _ = _attempts.Remove(id);
        }

        Apply([QueueOp.Resume(id), QueueOp.Hold(_environment.Connection(), _environment.Policy(), _environment.UsedBytes())]);
        Pump();
    }

    public void PauseAll()
    {
        Apply([QueueOp.PauseAll()]);
        foreach (var id in Active)
        {
            Cancel(id);
        }
    }

    public void ResumeAll()
    {
        lock (_gate)
        {
            _attempts.Clear();
        }

        Apply([QueueOp.ResumeAll(), QueueOp.Hold(_environment.Connection(), _environment.Policy(), _environment.UsedBytes())]);
        Pump();
    }

    /// <summary>Takes a row out of the queue and stops its transfer. The caller discards the file.</summary>
    public void Remove(string id)
    {
        Apply([QueueOp.Remove(id)]);
        Cancel(id);
        lock (_gate)
        {
            _ = _attempts.Remove(id);
            _ = _lastAttempt.Remove(id);
        }

        _ = _progress.TryRemove(id, out _);
    }

    /// <summary>
    /// The connection or the settings changed: the core pauses the rows the policy now holds back, running ones included, and releases the
    /// rows it no longer holds. The transfers of rows it paused stop, their partial files kept, and what may start does.
    /// </summary>
    public void NetworkChanged()
    {
        Apply([QueueOp.Hold(_environment.Connection(), _environment.Policy(), _environment.UsedBytes())]);
        foreach (var id in Active)
        {
            if (Queue.Get(id) is { Status: DownloadStatus.Paused })
            {
                Cancel(id);
            }
        }

        Pump();
    }

    /// <summary>The host's timer: the bytes each transfer has received are written into the queue and saved, so a kill loses a moment, not a download.</summary>
    public void Tick()
    {
        var ops = new List<QueueOp>();
        foreach (var id in Active)
        {
            if (_progress.TryGetValue(id, out var progress) && Queue.Get(id) is { } row && (long)progress.Received != row.DownloadedBytes)
            {
                ops.Add(QueueOp.Advance(id, (long)progress.Received, progress.Total));
            }
        }

        if (ops.Count > 0)
        {
            Apply(ops);
        }
    }

    /// <summary>
    /// Quitting: every transfer stops, its partial file kept, and the rows stay queued with the bytes they had, so the next launch resumes
    /// each. Nothing continues after this returns.
    /// </summary>
    public async Task QuitAsync()
    {
        Task[] running;
        lock (_gate)
        {
            running = [.. _flights.Values.Select(flight => flight.Task)];
            foreach (var flight in _flights.Values)
            {
                flight.Quit = true;
                flight.Token.Cancel();
            }
        }

        await _disposed.CancelAsync();
        await Task.WhenAll(running);
        Tick();
    }

    /// <summary>Completes when no transfer is running and none is waiting to start: for tests, and for a quit that has nothing to say.</summary>
    public async Task WhenIdleAsync()
    {
        while (true)
        {
            Task[] running;
            lock (_gate)
            {
                running = [.. _flights.Values.Select(flight => flight.Task)];
            }

            if (running.Length == 0)
            {
                return;
            }

            await Task.WhenAll(running);
        }
    }

    public void Dispose()
    {
        _disposed.Cancel();
        _disposed.Dispose();
    }

    private void Apply(IReadOnlyList<QueueOp> ops, bool reclaim = false)
    {
        lock (_gate)
        {
            var all = new List<QueueOp>();
            if (reclaim)
            {
                // A row in flight when the app was killed is queued again; then the policy decides what waits.
                all.Add(QueueOp.Reclaim());
                all.Add(QueueOp.Hold(_environment.Connection(), _environment.Policy(), _environment.UsedBytes()));
            }

            all.AddRange(ops);
            _queue = DownloadQueues.Apply(_queue, all).Queue;
            _environment.SaveQueue(_queue.Save());
        }

        Changed?.Invoke();
    }

    private void Cancel(string id)
    {
        lock (_gate)
        {
            if (_flights.TryGetValue(id, out var flight))
            {
                flight.Token.Cancel();
            }
        }
    }

    /// <summary>Starts what may start: the rows the core names, within the bound for the connection, less the transfers already running.</summary>
    private void Pump()
    {
        var connection = _environment.Connection();
        var policy = _environment.Policy();
        List<DownloadRow> start;
        lock (_gate)
        {
            var room = policy.ConcurrencyFor(connection) - _flights.Count;
            if (room <= 0)
            {
                return;
            }

            var startable = DownloadQueues.Apply(_queue, [], connection, policy).Startable;
            start = [.. startable.Where(id => !_flights.ContainsKey(id)).Take(room).Select(id => _queue.Get(id)!)];
            foreach (var row in start)
            {
                _flights[row.Id] = Launch(row);
            }
        }

        if (start.Count > 0)
        {
            Changed?.Invoke();
        }
    }

    private Flight Launch(DownloadRow row)
    {
        var token = new CancelToken();
        var flight = new Flight(token);
        flight.Task = Task.Run(() => Run(row, flight));
        return flight;
    }

    private void Run(DownloadRow row, Flight flight)
    {
        var reports = new Reports(_progress, row.Id);
        try
        {
            var landing = _transfer.Fetch(row, reports, flight.Token);
            lock (_gate)
            {
                _ = _flights.Remove(row.Id);
                _ = _attempts.Remove(row.Id);
                _lastAttempt[row.Id] = landing.Resumption;
                _queue = DownloadQueues.Apply(_queue, [QueueOp.Finish(row.Id, landing.Length, _environment.Now())]).Queue;
                _environment.SaveQueue(_queue.Save());
            }

            _ = _progress.TryRemove(row.Id, out _);
            Changed?.Invoke();
            Landed?.Invoke(row, landing);
        }
        catch (StoryArcException error)
        {
            Failed(row, error, flight);
        }
        finally
        {
            lock (_gate)
            {
                _ = _flights.Remove(row.Id);
            }

            flight.Token.Dispose();
            if (!flight.Quit)
            {
                Pump();
            }
        }
    }

    private void Failed(DownloadRow row, StoryArcException error, Flight flight)
    {
        if (error.Status == StoryArcStatus.Cancelled)
        {
            // A pause, a removal, a connection that changed or a quit: the queue already says what the row is, and the partial file is kept.
            lock (_gate)
            {
                if (_progress.TryGetValue(row.Id, out var progress) && _queue.Get(row.Id) is not null)
                {
                    _queue = DownloadQueues.Apply(_queue, [QueueOp.Advance(row.Id, (long)progress.Received, progress.Total)]).Queue;
                    _environment.SaveQueue(_queue.Save());
                }
            }

            Changed?.Invoke();
            return;
        }

        var failure = QueueFailure.Of(error);
        QueueOp op;
        TimeSpan? retryAfter = null;
        lock (_gate)
        {
            _ = _flights.Remove(row.Id);
            switch (error.Status)
            {
                case StoryArcStatus.Unreadable:
                    op = QueueOp.FailVerification(row.Id, QueueFailure.Unreadable);
                    break;
                case StoryArcStatus.Unsupported or StoryArcStatus.Storage or StoryArcStatus.Unauthorized or StoryArcStatus.NotFound:
                    op = QueueOp.Fail(row.Id, failure, retryable: false);
                    break;
                default:
                    var spent = _attempts.GetValueOrDefault(row.Id) + 1;
                    _attempts[row.Id] = spent;
                    var retry = spent < DownloadBackoff.AttemptLimit;
                    op = QueueOp.Fail(row.Id, failure, retryable: retry);
                    retryAfter = retry ? DownloadBackoff.After(spent) : null;
                    break;
            }

            _queue = DownloadQueues.Apply(_queue, [op]).Queue;
            _environment.SaveQueue(_queue.Save());
        }

        Changed?.Invoke();
        if (retryAfter is { } wait && !flight.Quit)
        {
            _ = Task.Run(() => RetryAfterAsync(row.Id, wait));
        }
    }

    private async Task RetryAfterAsync(string id, TimeSpan wait)
    {
        try
        {
            await _environment.Delay(wait, _disposed.Token);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        if (Queue.Get(id) is not { Status: DownloadStatus.Failed })
        {
            return;
        }

        // A retry the app makes keeps the failures it has counted; only the reader's own Resume forgets them.
        Apply([QueueOp.Resume(id), QueueOp.Hold(_environment.Connection(), _environment.Policy(), _environment.UsedBytes())]);
        Pump();
    }

    private sealed class Flight(CancelToken token)
    {
        public CancelToken Token { get; } = token;

        public Task Task { get; set; } = Task.CompletedTask;

        public volatile bool Quit;
    }

    private sealed class Reports(ConcurrentDictionary<string, DownloadProgress> progress, string id) : IProgress<DownloadProgress>
    {
        public void Report(DownloadProgress value) => progress[id] = value;
    }
}
