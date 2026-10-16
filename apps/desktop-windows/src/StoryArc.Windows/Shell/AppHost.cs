using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using StoryArc.Interop.Progress;
using StoryArc.Interop.Settings;
using StoryArc.Interop.Shell;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The one place that knows which windows are open (desktop-clients tasks 2.37, 2.38 and 2.41).
/// It restores the session at launch, opens a reader window per publication, answers the commands
/// of <see cref="CommandRouting"/>, keeps the session file current, repaints the chrome when the
/// settings or the system accent change, and quits with the last window. The decisions are in
/// StoryArc.Interop (<see cref="WindowRegistry{TWindow}"/>, <see cref="SessionRecorder"/>,
/// <see cref="SettingsStore"/>); this class only calls them and the WinUI window types.
/// </summary>
internal sealed class AppHost
{
    private readonly WindowRegistry<ReaderWindow> _readers = new();
    private readonly List<Window> _windows = [];
    private readonly SessionRecorder _session;
    private readonly ProgressWriter _progress = new(new PendingSeamProgressStore());
    private MainWindow? _library;

    public AppHost(DispatcherQueue dispatcher)
    {
        Settings = new SettingsStore(
            () => StateFiles.Read(StateFiles.SettingsPath),
            text => _ = StateFiles.Write(StateFiles.SettingsPath, text));
        SystemWatcher = new SystemSettingsWatcher(dispatcher);
        _session = new SessionRecorder(
            SessionState.Restore(StateFiles.Read(StateFiles.SessionPath)),
            text => _ = StateFiles.Write(StateFiles.SessionPath, text));

        _readers.LastWindowClosed += () => Application.Current.Exit();
        Settings.Changed += _ => Repaint();
        SystemWatcher.Changed += _ => Repaint();
    }

    public SettingsStore Settings { get; }

    public SystemSettingsWatcher SystemWatcher { get; }

    /// <summary>
    /// Opens what the last run left open. A session with no library window still opens one when
    /// no reader comes back either, so the app never starts with nothing on screen. Whether a
    /// publication can still be opened is the library's to say once the seam is bound (task 2.1);
    /// until then every saved reader reopens.
    /// </summary>
    public void Start()
    {
        var saved = _session.State;
        var plan = RestorationPlan.From(saved, _ => true);
        if (saved.Library is not null || plan.Reopen.Count == 0)
        {
            OpenLibrary();
        }

        foreach (var reader in plan.Reopen)
        {
            OpenReader(reader.PublicationId, reader);
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

    /// <summary>A second open of a publication finds its window and brings it to the front.</summary>
    public ReaderWindow OpenReader(string publicationId, ReaderWindowState? restored = null)
    {
        if (_readers.ReaderFor(publicationId) is { } existing)
        {
            existing.Activate();
            return existing;
        }

        var window = new ReaderWindow(this, publicationId, restored);
        _windows.Add(window);
        _readers.ReaderOpened(publicationId, window);
        window.Closed += (sender, args) => ReaderClosed(window);
        Repaint();
        window.Activate();
        _session.ReaderChanged(window.State());
        return window;
    }

    public void LibraryMoved(LibraryWindowState state) => _session.LibraryChanged(state);

    public void ReaderMoved(ReaderWindowState state) => _session.ReaderChanged(state);

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
        }
    }

    /// <summary>
    /// Writes every reading position and the session, then closes every window. The windows that
    /// close here stay in the session, so the next launch opens them again.
    /// </summary>
    public void Quit()
    {
        _ = _progress.FlushAll();
        _session.Quitting();
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

    private void LibraryClosed()
    {
        _windows.Remove(_library!);
        _library = null;
        _session.LibraryClosed();
        _readers.LibraryClosed();
    }

    private void ReaderClosed(ReaderWindow window)
    {
        _ = _progress.Flush(window.PublicationId);
        _windows.Remove(window);
        _session.ReaderClosed(window.PublicationId);
        _readers.ReaderClosed(window.PublicationId);
    }
}
