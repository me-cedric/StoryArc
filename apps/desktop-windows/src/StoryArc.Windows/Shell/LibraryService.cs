using System.Diagnostics;
using Microsoft.UI.Dispatching;
using StoryArc.Interop;
using StoryArc.Interop.Library;
using StoryArc.Interop.Opening;
using StoryArc.Interop.Sources;

namespace StoryArc.Windows.Shell;

/// <summary>One folder source as the library shows it: the folder, how it stands, and whether it is watched live.</summary>
internal sealed record SourceStatus(FolderSource Source, FolderAvailability Availability, bool IsWatched);

/// <summary>One file that could not be opened, named, with its reason, for the library's What couldn't be opened list.</summary>
internal sealed record Refusal(string Name, string Reason);

/// <summary>
/// The library behind the library window (desktop-clients tasks 2.43 and 2.47a): the folder sources
/// the reader chose, each scanned through the core (<see cref="ComicFolder"/>) on a worker thread, its
/// records with the progress the core keeps, the recent list behind the Jump List, and the files that
/// could not be opened. A source whose volume is gone is offline and keeps its records; a source the
/// app can no longer read needs access. Each available folder is watched with a
/// <see cref="FileSystemWatcher"/> that only schedules a rescan through the core, a network share is
/// polled instead, and <see cref="RescanSchedule"/> decides when.
/// </summary>
internal sealed class LibraryService : IDisposable
{
    private readonly DispatcherQueue _dispatcher;
    private readonly ProgressStore _progress;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly Dictionary<string, SourceState> _states = new(StringComparer.Ordinal);
    private readonly List<Refusal> _refusals = [];
    private FolderSourceList _list;

    public LibraryService(DispatcherQueue dispatcher, ProgressStore progress)
    {
        _dispatcher = dispatcher;
        _progress = progress;
        _list = FolderSourceList.Restore(StateFiles.Read(StateFiles.SourcesPath));
        Recent = RecentItems.Restore(StateFiles.Read(StateFiles.RecentPath)).Pruned(File.Exists);
    }

    /// <summary>Raised on the interface thread whenever the records, the sources, the refusals or the recent list change.</summary>
    public event Action? Changed;

    public RecentItems Recent { get; private set; }

    public IReadOnlyList<Refusal> Refusals => _refusals;

    public IReadOnlyList<SourceStatus> Sources =>
        _list.Sources.Select(source => _states.TryGetValue(source.Id, out var state)
            ? new SourceStatus(source, state.Availability, state.Schedule.IsWatched)
            : new SourceStatus(source, FolderAvailability.Available, true)).ToList();

    /// <summary>Every record of every source, offline sources included, so a library keeps its shape while a drive is away.</summary>
    public IReadOnlyList<LibraryRecord> Records =>
        _list.Sources.SelectMany(source => _states.TryGetValue(source.Id, out var state) ? state.Records : []).ToList();

    /// <summary>Whether the source a record came from can be read now.</summary>
    public bool IsAvailable(LibraryRecord record) =>
        !_states.TryGetValue(record.SourceId, out var state) || state.Availability == FolderAvailability.Available;

    /// <summary>Scans every stored folder, as at launch: the core reconciles by modification time and size.</summary>
    public void Start()
    {
        foreach (var source in _list.Sources)
        {
            Track(source);
        }

        _ = JumpLists.UpdateAsync(Recent);
    }

    /// <summary>A folder the reader chose in the folder picker, or agreed to add after a drop: it becomes a source and is scanned.</summary>
    public void AddFolder(string path)
    {
        var before = _list;
        _list = _list.Adding(path);
        if (ReferenceEquals(before, _list))
        {
            Rescan(_list.Sources.First(source => string.Equals(source.Path, Path.TrimEndingDirectorySeparator(path), StringComparison.OrdinalIgnoreCase)).Id);
            return;
        }

        _ = StateFiles.Write(StateFiles.SourcesPath, _list.Save());
        Track(_list.Sources[^1]);
    }

    /// <summary>The reader chose the folder of a source that needed access again: same source, new scan.</summary>
    public void ChooseAgain(string sourceId, string path)
    {
        RemoveFolder(sourceId);
        AddFolder(path);
    }

    public void RemoveFolder(string sourceId)
    {
        if (_states.Remove(sourceId, out var state))
        {
            state.Dispose();
        }

        _list = _list.Without(sourceId);
        _ = StateFiles.Write(StateFiles.SourcesPath, _list.Save());
        Changed?.Invoke();
    }

    /// <summary>The Refresh Sources command: every source now.</summary>
    public void RefreshAll()
    {
        foreach (var source in _list.Sources)
        {
            Rescan(source.Id);
        }
    }

    /// <summary>The window gained focus: sources that are not watched live are scanned now.</summary>
    public void Focused()
    {
        foreach (var state in _states.Values)
        {
            state.Schedule.Focused(_clock.Elapsed);
        }
    }

    /// <summary>The host's timer: every source whose schedule is due is scanned again, offline ones included, so a drive that returns comes back by itself.</summary>
    public void Tick()
    {
        var now = _clock.Elapsed;
        foreach (var (id, state) in _states)
        {
            var offlineRetry = state.Availability != FolderAvailability.Available && now - state.LastScan >= RescanSchedule.PollInterval;
            if (!state.IsScanning && (state.Schedule.IsDue(now) || offlineRetry))
            {
                Rescan(id);
            }
        }
    }

    /// <summary>A publication opened: it joins the recent list and the Jump List.</summary>
    public void Opened(string path, string title)
    {
        Recent = Recent.Opened(path, title, DateTimeOffset.Now);
        _ = StateFiles.Write(StateFiles.RecentPath, Recent.Save());
        _ = JumpLists.UpdateAsync(Recent);
        Changed?.Invoke();
    }

    /// <summary>Clears the reading history: the recent list and the Jump List are empty at once.</summary>
    public void ClearRecent()
    {
        Recent = RecentItems.Empty;
        _ = StateFiles.Write(StateFiles.RecentPath, Recent.Save());
        _ = JumpLists.UpdateAsync(Recent);
        Changed?.Invoke();
    }

    /// <summary>Names a file that could not be opened, newest first, where What couldn't be opened is shown.</summary>
    public void Refuse(Refusal refusal)
    {
        _refusals.Insert(0, refusal);
        Changed?.Invoke();
    }

    public void DismissRefusals()
    {
        _refusals.Clear();
        Changed?.Invoke();
    }

    public void Dispose()
    {
        foreach (var state in _states.Values)
        {
            state.Dispose();
        }

        _states.Clear();
    }

    private void Track(FolderSource source)
    {
        var state = new SourceState(source, new RescanSchedule(isWatched: true, _clock.Elapsed));
        _states[source.Id] = state;
        Rescan(source.Id);
    }

    private void Rescan(string sourceId)
    {
        if (!_states.TryGetValue(sourceId, out var state) || state.IsScanning)
        {
            return;
        }

        state.IsScanning = true;
        state.Schedule.Scanned(_clock.Elapsed);
        var source = state.Source;
        _ = Task.Run(() => Scan(source)).ContinueWith(
            task => _dispatcher.TryEnqueue(() => Apply(sourceId, task.Result)),
            TaskScheduler.Default);
    }

    /// <summary>Off the interface thread: the core's scan, then each record's progress from the core's store.</summary>
    private ScanResult Scan(FolderSource source)
    {
        try
        {
            using var folder = ComicFolder.Open(source.Path);
            var records = folder.Records()
                .Select(core => CoreLibrary.Record(core, ReadProgress(core.Identity), source.Id))
                .OfType<LibraryRecord>()
                .ToList();
            return new ScanResult(records, null);
        }
        catch (StoryArcException error)
        {
            return new ScanResult(null, error.Status);
        }
        catch (System.Text.Json.JsonException)
        {
            return new ScanResult(null, StoryArcStatus.Internal);
        }
    }

    private CoreProgress? ReadProgress(CoreIdentity identity)
    {
        try
        {
            return _progress.Read(identity);
        }
        catch (StoryArcException)
        {
            return null;
        }
    }

    private void Apply(string sourceId, ScanResult result)
    {
        if (!_states.TryGetValue(sourceId, out var state))
        {
            return;
        }

        state.IsScanning = false;
        state.LastScan = _clock.Elapsed;
        var volume = Path.GetPathRoot(state.Source.Path);
        var isVolumePresent = !string.IsNullOrEmpty(volume) && Directory.Exists(volume);
        state.Availability = FolderSourceList.Classify(result.Failure, isVolumePresent, state.Availability);
        if (result.Records is { } records)
        {
            state.Records = records;
        }

        state.Watch(stopped => _dispatcher.TryEnqueue(() =>
        {
            if (stopped)
            {
                state.Schedule.WatchingStopped();
            }

            state.Schedule.Changed(_clock.Elapsed);
        }));
        Changed?.Invoke();
    }

    private sealed record ScanResult(IReadOnlyList<LibraryRecord>? Records, StoryArcStatus? Failure);

    /// <summary>The live state of one source: its records, its schedule and its watcher.</summary>
    private sealed class SourceState(FolderSource source, RescanSchedule schedule) : IDisposable
    {
        private FileSystemWatcher? _watcher;

        public FolderSource Source { get; } = source;

        public RescanSchedule Schedule { get; } = schedule;

        public FolderAvailability Availability { get; set; } = FolderAvailability.Available;

        public IReadOnlyList<LibraryRecord> Records { get; set; } = [];

        public bool IsScanning { get; set; }

        public TimeSpan LastScan { get; set; }

        /// <summary>
        /// Watches an available folder once. A share (a UNC path) reports no reliable changes, and a
        /// watcher that cannot start or overflows falls back to the ten-second poll; the library then
        /// says once, in grey, that the folder is not watched live.
        /// </summary>
        public void Watch(Action<bool> changed)
        {
            if (Availability != FolderAvailability.Available)
            {
                _watcher?.Dispose();
                _watcher = null;
                return;
            }

            if (_watcher is not null || !Schedule.IsWatched)
            {
                return;
            }

            if (Source.Path.StartsWith(@"\\", StringComparison.Ordinal))
            {
                Schedule.WatchingStopped();
                return;
            }

            try
            {
                _watcher = new FileSystemWatcher(Source.Path)
                {
                    IncludeSubdirectories = true,
                    NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size,
                    InternalBufferSize = 64 * 1024,
                };
                // The watcher's events arrive on worker threads; the callback moves them to the interface thread.
                _watcher.Created += (_, _) => changed(false);
                _watcher.Deleted += (_, _) => changed(false);
                _watcher.Renamed += (_, _) => changed(false);
                _watcher.Changed += (_, _) => changed(false);
                _watcher.Error += (_, _) => changed(true);
                _watcher.EnableRaisingEvents = true;
            }
            catch (Exception error) when (error is ArgumentException or IOException or PlatformNotSupportedException or UnauthorizedAccessException)
            {
                _watcher?.Dispose();
                _watcher = null;
                Schedule.WatchingStopped();
            }
        }

        public void Dispose() => _watcher?.Dispose();
    }
}
