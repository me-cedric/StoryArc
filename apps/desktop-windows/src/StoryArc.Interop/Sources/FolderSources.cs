using System.Text.Json;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Sources;

/// <summary>How a folder source stands right now (desktop-experience "Choosing folders and keeping access").</summary>
public enum FolderAvailability
{
    /// <summary>Scanned and readable.</summary>
    Available,

    /// <summary>Its volume is not connected: shown offline in grey, and back by itself when the volume is (<c>source_state_unreachable</c>).</summary>
    Offline,

    /// <summary>The volume is there and the folder cannot be read: shown in grey as needing access, with one action to choose it again.</summary>
    NeedsAccess,
}

/// <summary>One folder the reader chose: a stable id, the stored path, and the name the library shows.</summary>
public sealed record FolderSource(string Id, string Path, string Name);

/// <summary>
/// The folders the reader chose, stored by path so access survives a relaunch without a second prompt
/// (desktop-clients task 2.43). A packaged full-trust app reads a path the user can read, so the path is
/// the whole grant on Windows (design.md, Decision 8). A folder chosen twice is one source.
/// </summary>
public sealed record FolderSourceList(IReadOnlyList<FolderSource> Sources)
{
    public static FolderSourceList Empty { get; } = new([]);

    /// <summary>The list with <paramref name="path"/> added, or the same list when it is there already. The id is the path folded, so it survives a relaunch.</summary>
    public FolderSourceList Adding(string path)
    {
        var trimmed = System.IO.Path.TrimEndingDirectorySeparator(path);
        if (Sources.Any(source => string.Equals(source.Path, trimmed, StringComparison.OrdinalIgnoreCase)))
        {
            return this;
        }

        var name = System.IO.Path.GetFileName(trimmed);
        var source = new FolderSource("folder:" + trimmed.ToUpperInvariant(), trimmed, string.IsNullOrEmpty(name) ? trimmed : name);
        return new FolderSourceList([.. Sources, source]);
    }

    public FolderSourceList Without(string id) => new(Sources.Where(source => source.Id != id).ToList());

    public string Save() => JsonSerializer.Serialize(this, FolderSourcesJsonContext.Default.FolderSourceList);

    public static FolderSourceList Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            return JsonSerializer.Deserialize(text, FolderSourcesJsonContext.Default.FolderSourceList) is { Sources: { } sources }
                ? new FolderSourceList(sources)
                : Empty;
        }
        catch (JsonException)
        {
            return Empty;
        }
    }

    /// <summary>
    /// What a scan's outcome means for the source. <paramref name="failure"/> is <c>null</c> after a scan
    /// that worked. A folder that is not there is offline when its volume is gone too (an unplugged
    /// drive, a share that is down) and needs access when the volume is there; any other refusal needs
    /// access as well. A cancelled scan changes nothing, so it answers <paramref name="previous"/>.
    /// </summary>
    public static FolderAvailability Classify(StoryArcStatus? failure, bool isVolumePresent, FolderAvailability previous) => failure switch
    {
        null => FolderAvailability.Available,
        StoryArcStatus.Cancelled => previous,
        StoryArcStatus.NotFound when !isVolumePresent => FolderAvailability.Offline,
        _ => FolderAvailability.NeedsAccess,
    };
}

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(FolderSourceList))]
internal sealed partial class FolderSourcesJsonContext : JsonSerializerContext;

/// <summary>
/// When a folder is scanned again (desktop-clients task 2.43; desktop-experience "Live folder
/// watching"). A change the watcher reports waits for a quiet moment, so a burst of thousands of
/// changes is one rescan, and never waits past the ten seconds the spec allows. A folder the
/// system cannot watch, a network share among them, is rescanned on a fixed interval of ten
/// seconds and when the window gains focus. Each rescan goes through the core's folder scan,
/// which reconciles by modification time and size instead of reading every archive again.
/// </summary>
public sealed class RescanSchedule
{
    /// <summary>How long the folder must be quiet after a change before it is scanned.</summary>
    public static readonly TimeSpan Quiet = TimeSpan.FromSeconds(1);

    /// <summary>The longest a reported change waits, however busy the folder stays.</summary>
    public static readonly TimeSpan MaxWait = TimeSpan.FromSeconds(8);

    /// <summary>The fixed interval of a folder that is not watched live: ten seconds or less, as the spec states.</summary>
    public static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(10);

    private TimeSpan? _firstChange;
    private TimeSpan? _lastChange;
    private TimeSpan _lastScan;

    public RescanSchedule(bool isWatched, TimeSpan now)
    {
        IsWatched = isWatched;
        _lastScan = now;
    }

    /// <summary>Whether the system reports this folder's changes; when it does not, the library says so once, in grey.</summary>
    public bool IsWatched { get; private set; }

    /// <summary>The watcher reported a change, or ran out of room and lost some: either way, scan.</summary>
    public void Changed(TimeSpan now)
    {
        _firstChange ??= now;
        _lastChange = now;
    }

    /// <summary>The watcher failed (its buffer overflowed, the share stopped reporting): fall back to polling.</summary>
    public void WatchingStopped() => IsWatched = false;

    /// <summary>The window gained focus: a folder that is not watched live is scanned now.</summary>
    public void Focused(TimeSpan now)
    {
        if (!IsWatched)
        {
            Changed(now);
        }
    }

    /// <summary>Whether a scan is due at <paramref name="now"/>.</summary>
    public bool IsDue(TimeSpan now)
    {
        if (_firstChange is { } first && _lastChange is { } last)
        {
            return now - last >= Quiet || now - first >= MaxWait;
        }

        return !IsWatched && now - _lastScan >= PollInterval;
    }

    /// <summary>A scan ran at <paramref name="now"/>.</summary>
    public void Scanned(TimeSpan now)
    {
        _firstChange = null;
        _lastChange = null;
        _lastScan = now;
    }
}
