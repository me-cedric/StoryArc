namespace StoryArc.Interop.Shell;

/// <summary>
/// Which windows are open: one library window and a reader window per publication. A second open
/// of a publication that already has a window finds that window instead of making another
/// (desktop-experience, "Opening a publication that is already open"), and when the last window
/// closes the app quits (desktop-experience, "Closing the last window on each system").
/// </summary>
/// <typeparam name="TWindow">The host's window type; the registry never calls into it.</typeparam>
public sealed class WindowRegistry<TWindow>
    where TWindow : class
{
    private readonly Dictionary<string, TWindow> _readers = new(StringComparer.Ordinal);
    private bool _isLibraryOpen;

    /// <summary>Raised once, when the last open window has closed.</summary>
    public event Action? LastWindowClosed;

    public bool IsLibraryOpen => _isLibraryOpen;

    public int OpenWindowCount => _readers.Count + (_isLibraryOpen ? 1 : 0);

    /// <summary>The publications that have a reader window, in the order they were opened.</summary>
    public IReadOnlyCollection<string> OpenPublications => _readers.Keys;

    /// <summary>The reader window of <paramref name="publicationId"/>, or <c>null</c> when none is open.</summary>
    public TWindow? ReaderFor(string publicationId) =>
        _readers.TryGetValue(publicationId, out var window) ? window : null;

    public void LibraryOpened() => _isLibraryOpen = true;

    public void LibraryClosed()
    {
        _isLibraryOpen = false;
        RaiseWhenEmpty();
    }

    /// <summary>
    /// Records a new reader window. Refused when the publication already has one: the caller must
    /// ask <see cref="ReaderFor"/> first and focus that window instead.
    /// </summary>
    public void ReaderOpened(string publicationId, TWindow window)
    {
        if (!_readers.TryAdd(publicationId, window))
        {
            throw new InvalidOperationException($"A reader window for {publicationId} is already open.");
        }
    }

    public void ReaderClosed(string publicationId)
    {
        _readers.Remove(publicationId);
        RaiseWhenEmpty();
    }

    private void RaiseWhenEmpty()
    {
        if (OpenWindowCount == 0)
        {
            LastWindowClosed?.Invoke();
        }
    }
}
