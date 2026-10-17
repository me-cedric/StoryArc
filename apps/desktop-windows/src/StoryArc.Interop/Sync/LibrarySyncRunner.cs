using StoryArc.Interop.Data;

namespace StoryArc.Interop.Sync;

/// <summary>Where the sync stands, for the one grey line the app shows. None of them is an error colour.</summary>
public enum SyncState
{
    /// <summary>No sync folder is chosen: nothing to do.</summary>
    NoFolder,

    /// <summary>Nothing has run yet this session.</summary>
    Idle,

    /// <summary>A sync is running now.</summary>
    Syncing,

    /// <summary>The last sync merged and wrote the document.</summary>
    Synced,

    /// <summary>The folder did not answer: the app reads normally and syncs when it returns.</summary>
    Unreachable,

    /// <summary>The document is from a newer app: left alone, named, and no sync until this app is updated.</summary>
    DocumentTooNew,
}

/// <summary>What one sync attempt came to.</summary>
public enum SyncResult
{
    /// <summary>Merged and written.</summary>
    Synced,

    /// <summary>Nothing was asked of the folder: none is chosen, or at quit the reading position had not changed.</summary>
    Skipped,

    /// <summary>The folder did not answer.</summary>
    Unreachable,

    /// <summary>The document is from a newer app.</summary>
    Refused,

    /// <summary>The location was slower than the time allowed: the caller went on, and the sync carries on or stops with the process.</summary>
    TimedOut,
}

/// <param name="Merge">The merge to apply to the library, when the sync produced one.</param>
/// <param name="Message">The core's sentence for a refusal or an unreachable folder, which the grey line may show.</param>
public sealed record SyncOutcome(SyncResult Result, LibraryMerge? Merge, string? Message);

/// <summary>
/// Synchronises the library while the app runs (desktop-clients task 3.23; desktop-experience, "Sync when the app runs"). Start and
/// quit are the moments the phones call foreground and background:
/// <list type="bullet">
/// <item>At start the sync runs on a worker, so the window never waits on it; the library shows Continue reading once it has merged, or
/// after <see cref="StartBudget"/> if the location is slow, and the merge is applied whenever it lands.</item>
/// <item>At quit the document is written once more if the reading position changed since the last sync, within
/// <see cref="QuitBudget"/> (five seconds), and the app quits whatever the result.</item>
/// <item>An unreachable folder is grey, never red, and a sync is tried again after <see cref="RetryInterval"/>.</item>
/// </list>
/// Calls overlap safely: a second sync asked for while one runs waits for that one instead of starting another.
/// </summary>
public sealed class LibrarySyncRunner
{
    /// <summary>How long the library waits for the start sync before it shows what it has.</summary>
    public static readonly TimeSpan StartBudget = TimeSpan.FromSeconds(2);

    /// <summary>How long a quit waits for the last write: five seconds, from the spec.</summary>
    public static readonly TimeSpan QuitBudget = TimeSpan.FromSeconds(5);

    /// <summary>How long after an unreachable folder the next attempt waits.</summary>
    public static readonly TimeSpan RetryInterval = TimeSpan.FromSeconds(60);

    private readonly Func<bool> _hasFolder;
    private readonly Func<string> _snapshot;
    private readonly Func<string, LibraryMerge> _sync;
    private readonly Action<LibraryMerge> _applied;
    private readonly Func<TimeSpan> _clock;
    private readonly Lock _gate = new();
    private Task<SyncOutcome>? _running;
    private bool _positionChanged;
    private TimeSpan? _lastFailure;

    /// <param name="hasFolder">Whether a sync folder is chosen.</param>
    /// <param name="snapshot">The library as this device holds it now, JSON for the core; read on the worker that syncs.</param>
    /// <param name="sync">Merges the snapshot with the document in the folder and writes it: <see cref="LibraryDocuments.Sync"/> with the folder and device filled in.</param>
    /// <param name="applied">Takes a merge into the app's own state; runs on the worker, so it must hand off to the interface thread itself.</param>
    /// <param name="clock">Time since the app started, for the retry; the system's clock when none is given.</param>
    public LibrarySyncRunner(
        Func<bool> hasFolder,
        Func<string> snapshot,
        Func<string, LibraryMerge> sync,
        Action<LibraryMerge> applied,
        Func<TimeSpan>? clock = null)
    {
        var started = System.Diagnostics.Stopwatch.StartNew();
        _clock = clock ?? (() => started.Elapsed);
        _hasFolder = hasFolder;
        _snapshot = snapshot;
        _sync = sync;
        _applied = applied;
    }

    public SyncState State { get; private set; } = SyncState.Idle;

    /// <summary>The core's sentence for the last refusal or unreachable folder.</summary>
    public string? LastMessage { get; private set; }

    /// <summary>Raised after <see cref="State"/> changes, on the worker that ran the sync.</summary>
    public event Action? StateChanged;

    /// <summary>The reading position changed since the last sync: the quit then writes the document once more.</summary>
    public void PositionChanged()
    {
        lock (_gate)
        {
            _positionChanged = true;
        }
    }

    /// <summary>Starts the sync of launch and answers at once with the task: the window does not wait on it.</summary>
    public Task<SyncOutcome> AtStartAsync() => Begin();

    /// <summary>
    /// The sync of quitting: skipped when the reading position has not changed, otherwise run and waited for up to
    /// <paramref name="budget"/> (five seconds when none is given). A slow location returns <see cref="SyncResult.TimedOut"/> and the app quits anyway.
    /// </summary>
    public async Task<SyncOutcome> AtQuitAsync(TimeSpan? budget = null)
    {
        lock (_gate)
        {
            if (!_positionChanged || !_hasFolder())
            {
                return new SyncOutcome(SyncResult.Skipped, null, null);
            }
        }

        try
        {
            return await Begin().WaitAsync(budget ?? QuitBudget);
        }
        catch (TimeoutException)
        {
            return new SyncOutcome(SyncResult.TimedOut, null, null);
        }
    }

    /// <summary>
    /// Called from the app's timer: after an unreachable folder the next attempt is made once <see cref="RetryInterval"/> has passed, and
    /// answers <c>null</c> when none is due.
    /// </summary>
    public Task<SyncOutcome>? RetryIfDue()
    {
        lock (_gate)
        {
            if (State != SyncState.Unreachable || _lastFailure is not { } failed || _clock() - failed < RetryInterval)
            {
                return null;
            }
        }

        return Begin();
    }

    private Task<SyncOutcome> Begin()
    {
        lock (_gate)
        {
            if (_running is { IsCompleted: false } running)
            {
                return running;
            }

            if (!_hasFolder())
            {
                State = SyncState.NoFolder;
                return Task.FromResult(new SyncOutcome(SyncResult.Skipped, null, null));
            }

            State = SyncState.Syncing;
            _running = Task.Run(Run);
            return _running;
        }
    }

    private SyncOutcome Run()
    {
        SyncOutcome outcome;
        SyncState state;
        try
        {
            var merge = _sync(_snapshot());
            _applied(merge);
            lock (_gate)
            {
                _positionChanged = false;
                _lastFailure = null;
            }

            outcome = new SyncOutcome(SyncResult.Synced, merge, null);
            state = SyncState.Synced;
        }
        catch (StoryArcException error) when (error.Status == StoryArcStatus.Unsupported)
        {
            outcome = new SyncOutcome(SyncResult.Refused, null, error.CoreMessage);
            state = SyncState.DocumentTooNew;
        }
        catch (Exception error) when (error is StoryArcException or IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            // Unreachable, or any other refusal of the place or of this device's own files: the app reads normally and tries again later.
            lock (_gate)
            {
                _lastFailure = _clock();
            }

            outcome = new SyncOutcome(SyncResult.Unreachable, null, error is StoryArcException core ? core.CoreMessage : error.Message);
            state = SyncState.Unreachable;
        }

        lock (_gate)
        {
            State = state;
            LastMessage = outcome.Message;
        }

        StateChanged?.Invoke();
        return outcome;
    }
}
