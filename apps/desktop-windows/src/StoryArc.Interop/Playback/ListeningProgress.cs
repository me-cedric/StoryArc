namespace StoryArc.Interop.Playback;

/// <summary>
/// Where a narrated book was left, in the core's progress store and in the phones' listening shape, so a position
/// heard here merges with one heard on a phone (ADR-0006). A single file is one part.
/// </summary>
public static class ListeningProgress
{
    /// <summary>Records <paramref name="offset"/> into a book of <paramref name="duration"/>.</summary>
    public static void Write(ProgressStore store, CoreIdentity identity, TimeSpan offset, TimeSpan duration, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(store);
        store.Write(CoreProgress.Listening(identity, offset, duration, now));
    }

    /// <summary>The offset a single-part book was left at, or <c>null</c> when nothing is recorded or the record is not one this file can resume.</summary>
    public static TimeSpan? Saved(ProgressStore store, CoreIdentity identity)
    {
        ArgumentNullException.ThrowIfNull(store);
        try
        {
            var record = store.Read(identity);
            if (record is null || record.IsFinished || record.Position is not { Kind: "listening", Part: 0, OffsetMillis: { } millis })
            {
                return null;
            }

            return TimeSpan.FromMilliseconds(millis);
        }
        catch (StoryArcException)
        {
            return null;
        }
    }
}
