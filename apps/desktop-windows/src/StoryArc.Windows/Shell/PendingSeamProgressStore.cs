using StoryArc.Interop.Progress;

namespace StoryArc.Windows.Shell;

/// <summary>
/// Where reading positions go until lane C's progress seam is bound (desktop-clients task 2.1,
/// then part two of 2.44): an in-memory store, so the cadence, the flush before a close and the
/// failure path run against a real <see cref="IProgressStore"/> from the first day. The session
/// file still carries each reader's page, which is what a relaunch restores meanwhile.
/// </summary>
internal sealed class PendingSeamProgressStore : IProgressStore
{
    private readonly Dictionary<string, int> _positions = new(StringComparer.Ordinal);

    public IReadOnlyDictionary<string, int> Positions => _positions;

    public void Write(string publicationId, int page) => _positions[publicationId] = page;
}
