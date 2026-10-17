namespace StoryArc.Interop.Progress;

/// <summary>
/// Where a reading position goes. The core's progress store (lane C's seam) implements it in
/// the app; the tests inject one that fails.
/// </summary>
public interface IProgressStore
{
    /// <summary>Writes the position. Throws when the write fails, for example on a full disk.</summary>
    void Write(string publicationId, int page);
}

/// <summary>
/// One write that failed: which publication, which page, and why. The diagnostic names it and the
/// next launch retries it (desktop-experience, "A write that fails").
/// </summary>
public sealed record ProgressWriteFailure(string PublicationId, int Page, string Reason);

/// <summary>
/// The cadence of desktop-experience "Closing a window and quitting the app" (desktop-clients
/// task 2.44, after 2.17). A turn schedules a write no later than five seconds after it, and a
/// burst of turns inside that window writes once, never once per frame. A window that closes and
/// an app that quits flush at once. A write that fails never stops the close or the quit: the
/// position stays in memory, the failure is named, and the next flush tries again.
/// </summary>
public sealed class ProgressWriter
{
    /// <summary>The latest a position is written after the turn that moved it.</summary>
    public static readonly TimeSpan Cadence = TimeSpan.FromSeconds(5);

    private readonly IProgressStore _store;
    private readonly Dictionary<string, int> _pending = new(StringComparer.Ordinal);
    private readonly List<ProgressWriteFailure> _failures = [];
    private TimeSpan? _dueAt;

    public ProgressWriter(IProgressStore store)
    {
        _store = store;
    }

    /// <summary>The positions not yet in the store, by publication.</summary>
    public IReadOnlyDictionary<string, int> Unsaved => _pending;

    /// <summary>Every write that failed since the writer was made, oldest first.</summary>
    public IReadOnlyList<ProgressWriteFailure> Failures => _failures;

    /// <summary>When the next <see cref="Tick"/> writes, or <c>null</c> while nothing is pending.</summary>
    public TimeSpan? DueAt => _dueAt;

    /// <summary>A page turn at <paramref name="now"/>. The first unsaved turn fixes the deadline; later turns inside it do not move it.</summary>
    public void Turned(string publicationId, int page, TimeSpan now)
    {
        _pending[publicationId] = page;
        _dueAt ??= now + Cadence;
    }

    /// <summary>The host's timer. Writes everything pending once the deadline has passed; returns whether it wrote.</summary>
    public bool Tick(TimeSpan now)
    {
        if (_dueAt is not { } due || now < due)
        {
            return false;
        }

        FlushAll();
        return true;
    }

    /// <summary>Writes one publication's position now, before its window closes. True when the store took it.</summary>
    public bool Flush(string publicationId)
    {
        if (!_pending.TryGetValue(publicationId, out var page))
        {
            return true;
        }

        var written = TryWrite(publicationId, page);
        if (written)
        {
            _pending.Remove(publicationId);
        }

        if (_pending.Count == 0)
        {
            _dueAt = null;
        }

        return written;
    }

    /// <summary>Writes every pending position now, before the app quits. True when every write succeeded.</summary>
    public bool FlushAll()
    {
        var allWritten = true;
        foreach (var publicationId in _pending.Keys.ToList())
        {
            allWritten &= Flush(publicationId);
        }

        _dueAt = _pending.Count == 0 ? null : _dueAt;
        return allWritten;
    }

    private bool TryWrite(string publicationId, int page)
    {
        try
        {
            _store.Write(publicationId, page);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            _failures.Add(new ProgressWriteFailure(publicationId, page, error.Message));
            return false;
        }
    }
}
