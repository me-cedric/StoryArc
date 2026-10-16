namespace StoryArc.Interop.Shell;

/// <summary>
/// Keeps the session file current as windows open, move and close (desktop-clients task 2.37;
/// desktop-experience "Windows come back after a quit or a crash"). Every change writes the new
/// text at once, so a crash restores the last state. A window the reader closes leaves the session;
/// once <see cref="Quitting"/> has been called nothing leaves it, because the windows that close
/// as the app quits are the ones the next launch must open again. A writer that throws is
/// ignored: a full disk never stops a window from closing.
/// </summary>
public sealed class SessionRecorder
{
    private readonly Action<string> _write;
    private bool _isQuitting;

    public SessionRecorder(SessionState initial, Action<string> write)
    {
        State = initial;
        _write = write;
    }

    public SessionState State { get; private set; }

    public void LibraryChanged(LibraryWindowState library) => Apply(State with { Library = library });

    public void ReaderChanged(ReaderWindowState reader) => Apply(State.WithReader(reader));

    public void LibraryClosed() => Apply(State with { Library = null });

    public void ReaderClosed(string publicationId) => Apply(State.WithoutReader(publicationId));

    /// <summary>The app is about to close every window: write the session as it is, and keep it so.</summary>
    public void Quitting()
    {
        Save();
        _isQuitting = true;
    }

    private void Apply(SessionState next)
    {
        if (_isQuitting)
        {
            return;
        }

        State = next;
        Save();
    }

    private void Save()
    {
        try
        {
            _write(State.Save());
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }
}
