using System.Collections.Concurrent;
using System.Globalization;
using Microsoft.UI.Dispatching;
using StoryArc.Interop;
using StoryArc.Interop.Credentials;
using StoryArc.Interop.Data;
using StoryArc.Interop.Downloads;
using StoryArc.Interop.Export;
using StoryArc.Interop.Library;
using StoryArc.Interop.Network;
using StoryArc.Interop.Settings;
using StoryArc.Interop.Sources;
using StoryArc.Interop.Sync;
using Windows.ApplicationModel;

namespace StoryArc.Windows.Shell;

/// <summary>What adding a source came to: the source when it was added, or the named problem, and what became of its credential.</summary>
internal sealed record AddOutcome(NetworkSource? Source, SourceFailure? Failure, CredentialResult? Credential);

/// <summary>
/// Everything wave 3 adds to the app, in one owner (desktop-clients tasks 3.21 to 3.23a): the core's runtime and vault, the network sources and
/// their credentials, the download queue and its coordinator, the sync, the shelves and the storage page's numbers. The decisions are in
/// StoryArc.Interop and tested there; this class calls them, keeps the files, and moves each change to the interface thread. Every network call
/// runs on a worker, and no credential is ever written by this class.
/// </summary>
internal sealed class NetworkServices : IDisposable
{
    private const string Device = "windows";
    private static readonly TimeSpan ConnectionPoll = TimeSpan.FromSeconds(5);

    private readonly DispatcherQueue _dispatcher;
    private readonly ProgressStore _progress;
    private readonly SettingsStore _settings;
    private readonly Func<IReadOnlyList<LibraryRecord>> _records;
    private readonly Action<string> _addFolder;
    private readonly ConcurrentDictionary<string, SourceCheck> _checks = new(StringComparer.Ordinal);
    private readonly CoreHttp _browse;
    private ConnectionState _connection;
    private TimeSpan _lastPoll;
    private readonly System.Diagnostics.Stopwatch _clock = System.Diagnostics.Stopwatch.StartNew();

    public NetworkServices(
        DispatcherQueue dispatcher,
        ProgressStore progress,
        SettingsStore settings,
        Func<IReadOnlyList<LibraryRecord>> records,
        Action<string> addFolder)
    {
        _dispatcher = dispatcher;
        _progress = progress;
        _settings = settings;
        _records = records;
        _addFolder = addFolder;

        Runtime = CoreRuntime.Create();
        Pins = PinBook.Restore(StateFiles.Read(StateFiles.PinsPath));
        _browse = CoreHttp.Create(Runtime, Pins);
        Vault = CredentialVault.Open(Runtime);
        Credentials = new SourceCredentials(Vault);
        Sources = NetworkSourceList.Restore(StateFiles.Read(StateFiles.NetworkSourcesPath));
        Shelves = ShelvesState.Restore(StateFiles.Read(StateFiles.ShelvesPath));
        Pinned = RestorePinned(StateFiles.Read(StateFiles.PinnedShelvesPath)).Pruned(Shelves);
        Edits = ShelfEditQueue.Restore(StateFiles.Read(StateFiles.ShelfEditsPath));
        _connection = SafeConnection();

        Directory.CreateDirectory(StateFiles.DownloadsFolder);
        Storage = new StorageUsage(
            StateFiles.DownloadsFolder,
            StateFiles.CoversFolder,
            [StateFiles.ProgressPath, StateFiles.ProgressPath + "-wal", StateFiles.ProgressPath + "-shm", StateFiles.ShelvesPath, StateFiles.PinnedShelvesPath, StateFiles.ShelfEditsPath]);

        var transfer = new CoreDownloadTransfer(Runtime, Pins, StateFiles.DownloadsFolder, AccessOf);
        Downloads = new DownloadCoordinator(
            transfer,
            DownloadQueue.Restore(StateFiles.Read(StateFiles.DownloadQueuePath)),
            new DownloadEnvironment(
                SafeConnection,
                () => new DownloadPolicySettings(UnmeteredOnly: _settings.Current.DownloadsUnmeteredOnly, StorageLimit: _settings.Current.StorageLimitBytes),
                () => SafeBytes(StateFiles.DownloadsFolder),
                () => DateTimeOffset.UtcNow,
                text => _ = StateFiles.Write(StateFiles.DownloadQueuePath, text),
                (wait, cancel) => Task.Delay(wait, cancel)));
        Downloads.Changed += Raise;
        Downloads.Landed += (row, landing) => _dispatcher.TryEnqueue(() => _addFolder(StateFiles.DownloadsFolder));

        Sync = new LibrarySyncRunner(
            () => !string.IsNullOrEmpty(_settings.Current.SyncFolder),
            BuildSnapshot,
            snapshot => LibraryDocuments.Sync(_settings.Current.SyncFolder!, Device, AppVersion, DateTimeOffset.UtcNow, snapshot),
            Apply);
        Sync.StateChanged += Raise;
        _settings.Changed += _ => Downloads.NetworkChanged();
    }

    /// <summary>Raised on the interface thread when sources, the queue, the shelves or the sync state change.</summary>
    public event Action? Changed;

    public CoreRuntime Runtime { get; }

    public PinBook Pins { get; }

    public CredentialVault Vault { get; }

    public SourceCredentials Credentials { get; }

    public NetworkSourceList Sources { get; private set; }

    public ShelvesState Shelves { get; private set; }

    public PinnedShelves Pinned { get; private set; }

    public ShelfEditQueue Edits { get; private set; }

    public StorageUsage Storage { get; }

    public DownloadCoordinator Downloads { get; }

    public LibrarySyncRunner Sync { get; }

    /// <summary>What the system says about the connection, as last polled.</summary>
    public ConnectionState Connection => _connection;

    public string AppVersion
    {
        get
        {
            var version = Package.Current.Id.Version;
            return string.Create(CultureInfo.InvariantCulture, $"{version.Major}.{version.Minor}.{version.Build}");
        }
    }

    /// <summary>The last check of a source, or <c>null</c> before one ran.</summary>
    public SourceCheck? CheckOf(string sourceId) => _checks.TryGetValue(sourceId, out var check) ? check : null;

    /// <summary>
    /// At launch: the queue resumes, and the sync starts on a worker. The library waits at most <see cref="LibrarySyncRunner.StartBudget"/> for it before it
    /// shows Continue reading, and the window never waits. Every source is checked once so the page can say which are away.
    /// </summary>
    public async Task StartAsync()
    {
        Downloads.Start();
        _ = Task.Run(CheckAll);
        try
        {
            _ = await Sync.AtStartAsync().WaitAsync(LibrarySyncRunner.StartBudget);
        }
        catch (TimeoutException)
        {
            // The sync goes on in the background and its merge is applied when it lands.
        }
    }

    /// <summary>The app's timer, every half second: progress is written into the queue, the connection is polled every five seconds, and a sync is retried when due.</summary>
    public void Tick()
    {
        Downloads.Tick();
        var now = _clock.Elapsed;
        if (now - _lastPoll >= ConnectionPoll)
        {
            _lastPoll = now;
            var current = SafeConnection();
            if (current != _connection)
            {
                _connection = current;
                Downloads.NetworkChanged();
                Raise();
            }

            _ = Sync.RetryIfDue();
        }
    }

    /// <summary>
    /// Quitting: the downloads stop with their partial files kept, then the sync document is written once more when the reading position changed,
    /// within five seconds, and the app quits whatever the result.
    /// </summary>
    public async Task QuitAsync()
    {
        await Downloads.QuitAsync();
        _ = await Sync.AtQuitAsync();
    }

    public void PositionChanged() => Sync.PositionChanged();

    // ---- Sources (task 3.21) ----

    /// <summary>
    /// Checks a source, and when it answers adds it: the record is saved without its credential, and the credential goes to the vault. A source that
    /// does not answer is not added, and the problem comes back named; an untrusted certificate comes back with its fingerprint to pin.
    /// </summary>
    public async Task<AddOutcome> AddSourceAsync(NetworkSourceKind kind, string name, string typedAddress, string? username, int? port, SourceSecrets entered)
    {
        var added = Sources.Adding(kind, name, typedAddress, username, port);
        var secrets = entered with { Password = added.Typed.Password ?? entered.Password };
        var check = await Task.Run(() => SourceProbe.Check(Runtime, _browse, added.Source, secrets));
        if (!check.IsConnected)
        {
            return new AddOutcome(null, check.Failure, null);
        }

        var credential = Save(added.Source, secrets);
        Sources = added.List;
        _checks[added.Source.Id] = check;
        _ = StateFiles.Write(StateFiles.NetworkSourcesPath, Sources.Save());
        Raise();
        return new AddOutcome(added.Source, null, credential);
    }

    /// <summary>The reader accepted the certificate after seeing its fingerprint: it is pinned for this host from now on.</summary>
    public void Trust(CertificateChallenge certificate)
    {
        _browse.Pin(certificate.Host, certificate.Fingerprint);
        _ = StateFiles.Write(StateFiles.PinsPath, Pins.Save());
    }

    public async Task<SourceCheck> TestAsync(NetworkSource source)
    {
        var secrets = SecretsOf(source);
        var check = await Task.Run(() => SourceProbe.Check(Runtime, _browse, source, secrets));
        _checks[source.Id] = check;
        Raise();
        return check;
    }

    public void Rename(NetworkSource source, string name)
    {
        Sources = Sources.Renaming(source.Id, name);
        _ = StateFiles.Write(StateFiles.NetworkSourcesPath, Sources.Save());
        Raise();
    }

    /// <summary>Removes a source: its record, its credential from the vault and the session, the shelves and offline edits it defined.</summary>
    public void RemoveSource(NetworkSource source)
    {
        Credentials.Forget(source);
        Sources = Sources.Without(source.Id);
        Shelves = ShelfRules.Apply(Shelves, [ShelfOp.RemoveSource(source.Id)]);
        Edits = Edits.RemovingAllFrom(source.Id);
        _ = _checks.TryRemove(source.Id, out _);
        SaveShelves();
        _ = StateFiles.Write(StateFiles.NetworkSourcesPath, Sources.Save());
        Raise();
    }

    /// <summary>Replaces the credential of a source that needs a sign-in.</summary>
    public CredentialResult SignInAgain(NetworkSource source, SourceSecrets entered) => Save(source, entered);

    /// <summary>A catalogue page, or a search of it, on a worker.</summary>
    public Task<OpdsPage> OpdsAsync(NetworkSource source, string? url, string? search)
    {
        var secrets = SecretsOf(source);
        return Task.Run(() => _browse.OpdsFeed(new OpdsRequest(source.Address, url, search, source.Username, secrets.Password, secrets.Token)));
    }

    /// <summary>A folder of a share, on a worker, over a connection made for the call.</summary>
    public Task<IReadOnlyList<SmbEntry>> ListShareAsync(NetworkSource source, string path)
    {
        var secrets = SecretsOf(source);
        return Task.Run(() =>
        {
            using var share = SmbShare.Connect(Runtime, new SmbConnection(source.Address, source.Port, source.Username, secrets.Password));
            return share.List(path);
        });
    }

    public Task<IReadOnlyList<KavitaLibrary>> KavitaLibrariesAsync(NetworkSource source) =>
        Task.Run(() => _browse.KavitaLibraries(source.Address, SecretsOf(source).ApiKey ?? string.Empty));

    public Task<IReadOnlyList<KavitaSeries>> KavitaSeriesAsync(NetworkSource source, long library) =>
        Task.Run(() => _browse.KavitaSeriesOf(source.Address, SecretsOf(source).ApiKey ?? string.Empty, library));

    public Task<IReadOnlyList<KavitaVolume>> KavitaVolumesAsync(NetworkSource source, long series) =>
        Task.Run(() => _browse.KavitaVolumes(source.Address, SecretsOf(source).ApiKey ?? string.Empty, series));

    // ---- Downloads (task 3.23) ----

    /// <summary>Queues a catalogue entry. A download the reader asks for here is by hand, so it runs on a metered connection too.</summary>
    public void Download(NetworkSource source, OpdsEntry entry)
    {
        if (entry.Best is not { } best)
        {
            return;
        }

        Downloads.Add("opds:" + source.Id + ":" + entry.Id, entry.Title, best.Href, source.Id, best.Length, byHand: true);
    }

    // ---- Shelves (task 3.23a) ----

    public void ApplyShelves(params ShelfOp[] ops)
    {
        Shelves = ShelfRules.Apply(Shelves, ops);
        Pinned = Pinned.Pruned(Shelves);
        SaveShelves();
        Sync.PositionChanged();
        Raise();
    }

    public void SetPinned(PinnedShelves pinned)
    {
        Pinned = pinned;
        _ = StateFiles.Write(StateFiles.PinnedShelvesPath, string.Join('\n', Pinned.Tokens));
        Raise();
    }

    // ---- Diagnostic and storage (task 3.23) ----

    public DiagnosticFacts Facts()
    {
        var sizes = Storage.Measure();
        return new DiagnosticFacts(
            AppVersion,
            NativeCore.Version(),
            "Windows " + Environment.OSVersion.Version,
            CultureInfo.CurrentCulture.Name,
            _settings.Current,
            sizes.Single(size => size.Kind == StoreKind.Downloads).Bytes,
            sizes.Single(size => size.Kind == StoreKind.Covers).Bytes,
            sizes.Single(size => size.Kind == StoreKind.Records).Bytes,
            Sources.Sources.Count,
            Downloads.Queue,
            Sync.State.ToString());
    }

    /// <summary>The diagnostic text, with every credential the vault holds and every host name removed by the core.</summary>
    public string DiagnosticText()
    {
        var held = new List<string>();
        foreach (var source in Sources.Sources)
        {
            foreach (var field in source.CredentialFields)
            {
                if (Credentials.Load(source.Id, field) is { } value)
                {
                    held.Add(value);
                }
            }
        }

        return DiagnosticReport.Text(Facts(), held);
    }

    public void Dispose()
    {
        Downloads.Dispose();
        _browse.Dispose();
        Vault.Dispose();
        Runtime.Dispose();
    }

    // ---- Internals ----

    private void CheckAll()
    {
        foreach (var source in Sources.Sources)
        {
            var secrets = SecretsOf(source);
            _checks[source.Id] = SourceProbe.Check(Runtime, _browse, source, secrets);
        }

        Raise();
    }

    /// <summary>Saves each credential that was entered. The answer is the first one that was not kept, or the last that was.</summary>
    private CredentialResult Save(NetworkSource source, SourceSecrets entered)
    {
        var result = new CredentialResult(CredentialOutcome.Stored, null, null);
        foreach (var (field, value) in new[]
        {
            (CredentialField.Password, entered.Password),
            (CredentialField.Token, entered.Token),
            (CredentialField.ApiKey, entered.ApiKey),
        })
        {
            if (string.IsNullOrEmpty(value))
            {
                continue;
            }

            var saved = Credentials.Save(source.Id, field, value);
            if (result.NeedsSignIn)
            {
                continue;
            }

            result = saved;
        }

        return result;
    }

    private SourceSecrets SecretsOf(NetworkSource source) => new(
        Password: Safe(() => Credentials.Load(source.Id, CredentialField.Password)),
        Token: Safe(() => Credentials.Load(source.Id, CredentialField.Token)),
        ApiKey: Safe(() => Credentials.Load(source.Id, CredentialField.ApiKey)));

    private DownloadAccess? AccessOf(string? sourceId)
    {
        if (sourceId is null || Sources.Find(sourceId) is not { } source)
        {
            return null;
        }

        var secrets = SecretsOf(source);
        return new DownloadAccess(source.Address, source.Username, secrets.Password, secrets.Token);
    }

    private static string? Safe(Func<string?> load)
    {
        try
        {
            return load();
        }
        catch (StoryArcException)
        {
            return null;
        }
    }

    private ConnectionState SafeConnection()
    {
        try
        {
            return Runtime.Connection();
        }
        catch (StoryArcException)
        {
            return ConnectionState.Unmetered;
        }
    }

    private static long SafeBytes(string folder)
    {
        try
        {
            return StorageBytes.Of(folder);
        }
        catch (StoryArcException)
        {
            return 0;
        }
    }

    private static PinnedShelves RestorePinned(string? text) =>
        string.IsNullOrWhiteSpace(text) ? PinnedShelves.None : new PinnedShelves([.. text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)]);

    private void SaveShelves()
    {
        _ = StateFiles.Write(StateFiles.ShelvesPath, Shelves.Save());
        _ = StateFiles.Write(StateFiles.ShelfEditsPath, Edits.Save());
        _ = StateFiles.Write(StateFiles.PinnedShelvesPath, string.Join('\n', Pinned.Tokens));
    }

    /// <summary>The library as this device holds it: the network sources without a credential, the pins, the shelves and every reading position the progress store knows.</summary>
    private string BuildSnapshot()
    {
        var needSignIn = Sources.Sources.Where(source => !Credentials.Holds(source) && source.CredentialFields.Count > 0 && source.Username is not null)
            .Select(source => source.Id).ToHashSet();
        var positions = new List<string>();
        foreach (var record in _records())
        {
            if (record.Core is { } core)
            {
                var json = _progress.ReadJson(core.Identity.ToJson());
                if (json != "null")
                {
                    positions.Add(json);
                }
            }
        }

        return LibrarySnapshots.Build(Sources.ToDocumentSources(needSignIn), Pins, Shelves, positions, Pinned.Tokens);
    }

    /// <summary>A merge from the sync document: positions go to the progress store, shelves, pins and the sources another device added are kept.</summary>
    private void Apply(LibraryMerge merge)
    {
        foreach (var record in merge.ProgressRecords())
        {
            try
            {
                _progress.WriteJson(record);
            }
            catch (StoryArcException)
            {
                // A record the store refuses is left out; the rest still merge.
            }
        }

        foreach (var pin in merge.Pins())
        {
            _ = Pins.Add(pin.Host, pin.Fingerprint);
        }

        _dispatcher.TryEnqueue(() =>
        {
            Shelves = merge.Shelves();
            Pinned = new PinnedShelves(merge.PinnedShelves()).Pruned(Shelves);
            Sources = Sources.Adopting(merge.Sources());
            SaveShelves();
            _ = StateFiles.Write(StateFiles.NetworkSourcesPath, Sources.Save());
            _ = StateFiles.Write(StateFiles.PinsPath, Pins.Save());
            Raise();
        });
    }

    private void Raise() => _dispatcher.TryEnqueue(() => Changed?.Invoke());
}
