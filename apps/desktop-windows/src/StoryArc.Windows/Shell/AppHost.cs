using System.Diagnostics;
using System.Globalization;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using StoryArc.Interop;
using StoryArc.Interop.Opening;
using StoryArc.Interop.Progress;
using StoryArc.Interop.Settings;
using StoryArc.Interop.Shell;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The one place that knows which windows are open (desktop-clients tasks 2.37 to 2.44). It restores
/// the session at launch, opens what the launch asked for, opens a reader window per publication
/// through the core, answers the commands of <see cref="CommandRouting"/>, keeps the session file and
/// the reading positions current, repaints the chrome when the settings or the system accent change,
/// and quits with the last window. The decisions are in StoryArc.Interop; this class calls them and
/// the WinUI window types.
/// </summary>
internal sealed class AppHost
{
    private static readonly TimeSpan TickInterval = TimeSpan.FromMilliseconds(500);

    private readonly WindowRegistry<IPublicationWindow> _readers = new();
    private readonly List<Window> _windows = [];
    private readonly HashSet<string> _opening = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ProgressTarget> _targets = new(StringComparer.OrdinalIgnoreCase);
    private readonly SessionRecorder _session;
    private readonly ProgressStore? _coreProgress;
    private readonly CoreProgressStore? _savedPages;
    private readonly ProgressWriter _progress;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly DispatcherQueueTimer _timer;
    private MainWindow? _library;
    private bool _isQuitting;

    public AppHost(DispatcherQueue dispatcher)
    {
        Settings = new SettingsStore(
            () => StateFiles.Read(StateFiles.SettingsPath),
            text => _ = StateFiles.Write(StateFiles.SettingsPath, text));
        SystemWatcher = new SystemSettingsWatcher(dispatcher);
        _session = new SessionRecorder(
            SessionState.Restore(StateFiles.Read(StateFiles.SessionPath)),
            text => _ = StateFiles.Write(StateFiles.SessionPath, text));

        // The core's progress store. A store that cannot open leaves positions in memory, named as
        // failed writes, and the session file still carries each reader's page.
        StateFiles.ApplyPendingRecordsClear();
        try
        {
            _coreProgress = ProgressStore.Open(StateFiles.ProgressPath);
            _savedPages = new CoreProgressStore(_coreProgress, Target, () => DateTimeOffset.Now);
        }
        catch (StoryArcException)
        {
            _coreProgress = null;
        }

        _progress = new ProgressWriter((IProgressStore?)_savedPages ?? new UnavailableProgressStore());
        Library = _coreProgress is null ? null : new LibraryService(dispatcher, _coreProgress);
        Network = CreateNetwork(dispatcher);
        Playback = CreatePlayback(dispatcher);

        _readers.LastWindowClosed += Exit;
        Settings.Changed += _ => Repaint();
        SystemWatcher.Changed += _ => Repaint();

        _timer = dispatcher.CreateTimer();
        _timer.Interval = TickInterval;
        _timer.Tick += (sender, args) =>
        {
            _ = _progress.Tick(_clock.Elapsed);
            Library?.Tick();
            Network?.Tick();
        };
    }

    public SettingsStore Settings { get; }

    public SystemSettingsWatcher SystemWatcher { get; }

    /// <summary>The folder sources and their records; <c>null</c> only when the core's store could not open.</summary>
    public LibraryService? Library { get; }

    /// <summary>The network sources, the vault, the downloads, the sync and the shelves (wave 3); <c>null</c> when the core's store or runtime could not start.</summary>
    internal NetworkServices? Network { get; }

    /// <summary>The one player (tasks 4.19 and 4.20), or <c>null</c> when the media stack could not be made.</summary>
    internal PlaybackService? Playback { get; }

    /// <summary>
    /// Opens what the last run left open, then what this launch asked for. A launch for files opens
    /// their readers without the library in front of them; otherwise a session with no library window
    /// still opens one when no reader comes back, so the app never starts with nothing on screen. A
    /// saved reader whose file is gone does not reopen, and the library names it in grey.
    /// </summary>
    public void Start(LaunchRequest launch)
    {
        _timer.Start();
        _ = StartLibraryAsync();

        var saved = _session.State;
        var plan = RestorationPlan.From(saved, File.Exists);
        if (!launch.OpensFiles && (saved.Library is not null || plan.Reopen.Count == 0))
        {
            OpenLibrary();
        }

        foreach (var skipped in plan.Skipped)
        {
            _session.ReaderClosed(skipped);
            Library?.Refuse(new Refusal(Path.GetFileName(skipped), Format("library_folderUnavailable___", "“{0}” can no longer be read", Path.GetFileName(skipped))));
        }

        foreach (var reader in plan.Reopen)
        {
            _ = OpenReaderAsync(reader.PublicationId, reader);
        }

        OpenPaths(launch.Paths, launch.Origin);
    }

    /// <summary>
    /// The library scans its folders once the sync has merged, or after the short budget when the sync location is slow, so Continue reading shows the
    /// merged positions and the window never waits on the network.
    /// </summary>
    private async Task StartLibraryAsync()
    {
        if (Network is { } network)
        {
            await network.StartAsync();
        }

        Library?.Start();
    }

    /// <summary>A later launch redirected here: open what it carries, or bring the app forward.</summary>
    public void Activate(LaunchRequest launch)
    {
        if (launch.OpensFiles)
        {
            OpenPaths(launch.Paths, launch.Origin);
        }
        else
        {
            OpenLibrary().Activate();
        }
    }

    /// <summary>The library window, opened first if the reader had closed it.</summary>
    public MainWindow OpenLibrary()
    {
        if (_library is not null)
        {
            return _library;
        }

        var restored = _session.State.Library;
        _library = new MainWindow(this, restored);
        _windows.Add(_library);
        _readers.LibraryOpened();
        _library.Closed += (sender, args) => LibraryClosed();
        Repaint();
        _library.Activate();
        return _library;
    }

    /// <summary>
    /// Opens files from a drop, the command line, Explorer, the Jump List or a picker. Each supported
    /// file opens in its own reader window up to the window limit; a folder is offered as a library;
    /// everything else is refused by name in the library's What couldn't be opened list.
    /// </summary>
    public void OpenPaths(IEnumerable<string> paths, OpenOrigin origin)
    {
        var plan = OpenRequest.Plan(paths, File.Exists, Directory.Exists);
        if (plan.IsEmpty)
        {
            return;
        }

        foreach (var refusal in plan.Refused)
        {
            Library?.Refuse(new Refusal(refusal.Name, ReasonFor(refusal)));
        }

        foreach (var path in plan.Overflow)
        {
            Library?.Refuse(new Refusal(
                Path.GetFileName(path),
                Format("open_overflow___", "Not opened: StoryArc opens {0} files at once. Open it from your library.", OpenRequest.WindowLimit)));
        }

        foreach (var path in plan.Open)
        {
            _ = OpenReaderAsync(path, restored: null);
        }

        if (plan.Folders.Count > 0 || (plan.Open.Count == 0 && (plan.Refused.Count > 0 || plan.Overflow.Count > 0)))
        {
            var library = OpenLibrary();
            foreach (var folder in plan.Folders)
            {
                _ = library.OfferFolderAsync(folder);
            }
        }

        EnsureAWindow();
    }

    /// <summary>
    /// Opens a publication in its reader window through the core, off the interface thread. A second
    /// open of a publication brings its window to the front. A refusal is named in the library.
    /// </summary>
    public async Task OpenReaderAsync(string path, ReaderWindowState? restored)
    {
        if (_readers.ReaderFor(path) is { } existing)
        {
            existing.Activate();
            return;
        }

        if (!_opening.Add(path))
        {
            return;
        }

        try
        {
            var (window, title) = await OpenWindowAsync(path, restored);
            _windows.Add((Window)window);
            _readers.ReaderOpened(path, window);
            ((Window)window).Closed += (sender, args) => ReaderClosed(window);
            Repaint();
            window.Activate();
            _session.ReaderChanged(window.State());
            Library?.Opened(path, title);
        }
        catch (StoryArcException error)
        {
            Library?.Refuse(new Refusal(Path.GetFileName(path), ReasonFor(path, error)));
            OpenLibrary();
        }
        catch (System.Text.Json.JsonException)
        {
            // A record the core wrote and this build cannot read: a defect, named rather than a crash.
            Library?.Refuse(new Refusal(Path.GetFileName(path), Strings.Get("library_skipped_reason_unknown", "it could not be read")));
            OpenLibrary();
        }
        finally
        {
            _opening.Remove(path);
        }
    }

    /// <summary>The window of a publication by its format: the comic reader (wave 2), the EPUB reader (4.16) or the PDF reader (4.17).</summary>
    private async Task<(IPublicationWindow Window, string Title)> OpenWindowAsync(string path, ReaderWindowState? restored)
    {
        var extension = Path.GetExtension(path);
        if (OpenRequest.Audio.Contains(extension))
        {
            if (Playback is not { } playback)
            {
                throw new StoryArcException("playback", StoryArcStatus.Unsupported, Strings.Get("player_finished_stopped", "Playback stopped"));
            }

            var title = Path.GetFileNameWithoutExtension(path);
            var seconds = restored is { Page: > 0 } ? restored.Page - 1 : 0;
            playback.PlayNarrated(path, title, author: null, coverPath: null, TimeSpan.FromSeconds(seconds));
            return (new PlayerWindow(this, playback, path, restored), title);
        }

        if (string.Equals(extension, ".epub", StringComparison.OrdinalIgnoreCase))
        {
            var epub = await OpenedEpub.OpenAsync(path);
            var startPosition = restored is { Page: > 0 } ? restored.Page - 1 : _savedPages?.SavedPage(epub.Identity) ?? 0;
            _targets[path] = new ProgressTarget(epub.Identity, epub.PositionCount);
            return (new EpubReaderWindow(this, epub, restored, startPosition), epub.Title);
        }

        var opened = string.Equals(extension, ".pdf", StringComparison.OrdinalIgnoreCase)
            ? await OpenedPublication.OpenPdfAsync(path)
            : await OpenedPublication.OpenAsync(path);
        var start = restored is { Page: > 0 } ? restored.Page - 1 : _savedPages?.SavedPage(opened.Record.Identity) ?? 0;
        _targets[path] = new ProgressTarget(opened.Record.Identity, opened.PageCount);
        return (new ReaderWindow(this, opened, restored, start), opened.Record.DisplayTitle);
    }

    public void LibraryMoved(LibraryWindowState state) => _session.LibraryChanged(state);

    public void ReaderMoved(ReaderWindowState state) => _session.ReaderChanged(state);

    /// <summary>A page turn: written within the cadence, never once per frame.</summary>
    public void PageTurned(string publicationId, int page)
    {
        _progress.Turned(publicationId, page, _clock.Elapsed);
        Network?.PositionChanged();
    }

    /// <summary>
    /// Whether closing <paramref name="window"/> would end the app with a download still running: it is the last window, and the reader has not agreed
    /// yet. The window then asks first, as the Quit command does.
    /// </summary>
    internal bool ShouldAskBeforeClosing(Window window) =>
        !_isQuitting && _windows.Count == 1 && _windows[0] == window && Network?.Downloads.NeedsQuitPrompt == true;

    /// <summary>The command of the menu or the shortcut, asked from <paramref name="window"/>.</summary>
    public void Invoke(string commandId, Window window)
    {
        switch (commandId)
        {
            case "closeWindow":
                window.Close();
                break;
            case "quit":
                Quit();
                break;
            case "settings":
                OpenLibrary().ShowPreferences();
                break;
            case "fullScreen" when window is ReaderWindow reader:
                reader.ToggleFullScreen();
                break;
            case "openFile":
                _ = PickFileAsync(window);
                break;
            case "addSource":
                _ = OpenLibrary().PickFolderAsync(sourceToReplace: null);
                break;
            case "refreshSources":
                Library?.RefreshAll();
                break;
            case "playPause" when window is not PlayerWindow:
                Playback?.TogglePlayPause();
                break;
            case "skipBack" when window is not PlayerWindow:
                Playback?.SkipBack();
                break;
            case "skipForward" when window is not PlayerWindow:
                Playback?.SkipForward();
                break;
            default:
                if (window is IPublicationWindow pages)
                {
                    pages.Run(commandId);
                }
                else if (window is MainWindow library)
                {
                    library.Run(commandId);
                }

                break;
        }
    }

    /// <summary>
    /// Quits. A download in progress asks first: it pauses, keeps its partial file and resumes at the next launch. Then every reading position and the
    /// session are written, the downloads stop, the sync document is written once more when the position changed (within five seconds, and the app quits
    /// whatever the result), and every window closes. The windows that close here stay in the session, so the next launch opens them again.
    /// </summary>
    public void Quit() => _ = QuitAsync();

    private async Task QuitAsync()
    {
        if (_isQuitting)
        {
            return;
        }

        if (Network?.Downloads.NeedsQuitPrompt == true && !await OpenLibrary().ConfirmQuitAsync())
        {
            return;
        }

        _isQuitting = true;
        _ = _progress.FlushAll();
        _session.Quitting();
        if (Network is { } network)
        {
            await network.QuitAsync();
        }

        foreach (var window in _windows.ToList())
        {
            window.Close();
        }
    }

    /// <summary>Applies the appearance and the chrome accent to every open window.</summary>
    public void Repaint()
    {
        var settings = Settings.Current;
        var theme = AppearanceTheme.For(settings.Appearance) switch
        {
            ThemeKind.Light => ElementTheme.Light,
            ThemeKind.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
        foreach (var window in _windows)
        {
            if (window.Content is FrameworkElement root)
            {
                root.RequestedTheme = theme;
            }
        }

        AccentApplier.Apply(ChromeAccent.Resolve(settings.Accent, SystemWatcher.SystemAccent()), _windows);
    }

    /// <summary>The sentence of a refusal the plan made before asking the core.</summary>
    internal static string ReasonFor(OpenRefusal refusal) => refusal.Reason switch
    {
        RefusalReason.Cb7 => Strings.Get("library_cell_cannotOpen_cb7", "This is a CB7 file, which StoryArc does not read."),
        RefusalReason.NotAFormat => Format("library_skipped_reason_unsupported___", "{0} is not a format StoryArc reads", refusal.Name),
        _ => Format("library_folderUnavailable___", "“{0}” can no longer be read", refusal.Name),
    };

    /// <summary>The sentence of a refusal the core made: its own words for a format or a codec, the catalogue's for the rest.</summary>
    internal static string ReasonFor(string path, StoryArcException error)
    {
        var name = Path.GetFileName(path);
        return error.Status switch
        {
            StoryArcStatus.NotFound => Format("library_folderUnavailable___", "“{0}” can no longer be read", name),
            StoryArcStatus.Unreadable => Format("open_in_damaged___", "{0} could not be read. It may be damaged.", name),
            _ => error.CoreMessage ?? Strings.Get("library_skipped_reason_unknown", "it could not be read"),
        };
    }

    private static string Format(string key, string fallback, object argument) =>
        string.Format(CultureInfo.CurrentCulture, Strings.Get(key, fallback), argument);

    private ProgressTarget? Target(string publicationId) => _targets.GetValueOrDefault(publicationId);

    private async Task PickFileAsync(Window owner)
    {
        var picker = new Microsoft.Windows.Storage.Pickers.FileOpenPicker(owner.AppWindow.Id);
        foreach (var extension in OpenRequest.Associated)
        {
            picker.FileTypeFilter.Add(extension);
        }

        var picked = await picker.PickSingleFileAsync();
        if (picked is not null)
        {
            OpenPaths([picked.Path], OpenOrigin.Picker);
        }
    }

    private void EnsureAWindow()
    {
        if (_windows.Count == 0 && _opening.Count == 0)
        {
            OpenLibrary();
        }
    }

    private void LibraryClosed()
    {
        _windows.Remove(_library!);
        _library = null;
        _session.LibraryClosed();
        _readers.LibraryClosed();
    }

    private void ReaderClosed(IPublicationWindow window)
    {
        _ = _progress.Flush(window.PublicationId);
        _targets.Remove(window.PublicationId);
        _windows.Remove((Window)window);
        _session.ReaderClosed(window.PublicationId);
        _readers.ReaderClosed(window.PublicationId);
    }

    private void Exit()
    {
        _ = _progress.FlushAll();
        _timer.Stop();
        if (!_isQuitting && Network is { } network)
        {
            // The last window closed without the Quit command: stop the transfers and write the sync document, off the interface thread, for at most six seconds.
            _ = Task.Run(network.QuitAsync).Wait(TimeSpan.FromSeconds(6));
        }

        Playback?.Dispose();
        Network?.Dispose();
        Library?.Dispose();
        _coreProgress?.Dispose();
        Application.Current.Exit();
    }

    /// <summary>Brings the player window to the front, or opens it for what plays. Nothing happens while nothing plays.</summary>
    public void OpenPlayer()
    {
        if (Playback is not { } playback || playback.Model.Item is not { } item)
        {
            return;
        }

        if (_readers.ReaderFor(item.PublicationId) is PlayerWindow existing)
        {
            existing.Activate();
            return;
        }

        if (_readers.ReaderFor(item.PublicationId) is { } reader)
        {
            // The voice reads a publication whose own window is open: that window is the way back to the book.
            reader.Activate();
            return;
        }

        var window = new PlayerWindow(this, playback, item.PublicationId, restored: null);
        _windows.Add(window);
        _readers.ReaderOpened(item.PublicationId, window);
        window.Closed += (sender, args) => ReaderClosed(window);
        window.Activate();
    }

    private PlaybackService? CreatePlayback(DispatcherQueue dispatcher)
    {
        try
        {
            return new PlaybackService(dispatcher, (publicationId, position) => Network?.PositionChanged());
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException or TypeLoadException)
        {
            // The media stack is absent (a Windows build with media features removed): the library and the readers still work.
            return null;
        }
    }

    private NetworkServices? CreateNetwork(DispatcherQueue dispatcher)
    {
        var library = Library;
        if (_coreProgress is null || library is null)
        {
            return null;
        }

        try
        {
            return new NetworkServices(dispatcher, _coreProgress, Settings, () => library.Records, path => library.AddFolder(path));
        }
        catch (StoryArcException)
        {
            // The core's runtime did not start: the library still works, and the network sources are absent.
            return null;
        }
    }

    /// <summary>Where positions go when the core's store could not open: every write fails, by name, and stays in memory.</summary>
    private sealed class UnavailableProgressStore : IProgressStore
    {
        public void Write(string publicationId, int page) =>
            throw new IOException("The progress store could not be opened.");
    }
}
