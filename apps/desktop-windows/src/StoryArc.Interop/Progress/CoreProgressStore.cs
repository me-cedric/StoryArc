namespace StoryArc.Interop.Progress;

/// <summary>What the store needs to know about an open publication to record a position in it.</summary>
/// <param name="Identity">The identity the core gave the publication.</param>
/// <param name="PageCount">Its number of pages, so the record says "page i of n" and the last page finishes it.</param>
public sealed record ProgressTarget(CoreIdentity Identity, int PageCount);

/// <summary>
/// The <see cref="IProgressStore"/> the app runs on: the core's progress store behind the seam
/// (desktop-clients task 2.44, part two). A position is the page index from zero. A write the core
/// refuses, a full disk among them, surfaces as an <see cref="IOException"/> naming the core's
/// sentence, which <see cref="ProgressWriter"/> records and retries; a publication the store has
/// not been told about is an <see cref="InvalidOperationException"/>.
/// </summary>
public sealed class CoreProgressStore : IProgressStore
{
    private readonly ProgressStore _store;
    private readonly Func<string, ProgressTarget?> _target;
    private readonly Func<DateTimeOffset> _now;

    /// <param name="store">The open core store; the caller owns it and disposes it after the last flush.</param>
    /// <param name="target">The identity and page count of a publication id, or <c>null</c> when it is not open.</param>
    /// <param name="now">The clock that stamps each record.</param>
    public CoreProgressStore(ProgressStore store, Func<string, ProgressTarget?> target, Func<DateTimeOffset> now)
    {
        _store = store;
        _target = target;
        _now = now;
    }

    public void Write(string publicationId, int page)
    {
        var target = _target(publicationId)
            ?? throw new InvalidOperationException($"No open publication is known as {publicationId}.");
        try
        {
            _store.Write(CoreProgress.Page(target.Identity, page, target.PageCount, _now()));
        }
        catch (StoryArcException error)
        {
            throw new IOException(error.CoreMessage ?? error.Message, error);
        }
    }

    /// <summary>The page index from zero a publication was left on, or <c>null</c> when nothing is recorded.</summary>
    public int? SavedPage(CoreIdentity identity)
    {
        try
        {
            return _store.Read(identity)?.Position is { Kind: "page" } position ? position.Index : null;
        }
        catch (StoryArcException)
        {
            return null;
        }
    }
}
