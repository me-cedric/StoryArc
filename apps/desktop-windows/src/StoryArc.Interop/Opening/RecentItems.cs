using System.Text.Json;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Opening;

/// <summary>One publication the reader opened: its path, the title the Jump List shows, and when.</summary>
public sealed record RecentItem(string Path, string Title, DateTimeOffset OpenedAt);

/// <summary>
/// The recent publications behind the Jump List and the File menu's Open Recent (desktop-clients
/// task 2.42; desktop-experience "Recently opened files" and "Recent items in the system's
/// launcher"): newest first, one entry per file, at most <see cref="Limit"/>. A file that no longer
/// exists drops out without an error, and clearing the history empties the list at once.
/// </summary>
public sealed record RecentItems(IReadOnlyList<RecentItem> Items)
{
    /// <summary>How many recent publications the list keeps.</summary>
    public const int Limit = 10;

    public static RecentItems Empty { get; } = new([]);

    /// <summary>The list after <paramref name="path"/> was opened at <paramref name="at"/>: it moves to the front.</summary>
    public RecentItems Opened(string path, string title, DateTimeOffset at) =>
        new(Items
            .Where(item => !string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase))
            .Prepend(new RecentItem(path, title, at))
            .Take(Limit)
            .ToList());

    /// <summary>The list without the files that are gone. The same list when nothing is.</summary>
    public RecentItems Pruned(Func<string, bool> exists)
    {
        var kept = Items.Where(item => exists(item.Path)).ToList();
        return kept.Count == Items.Count ? this : new RecentItems(kept);
    }

    public string Save() => JsonSerializer.Serialize(this, RecentItemsJsonContext.Default.RecentItems);

    /// <summary>The saved list; anything missing or damaged is an empty list, never an error.</summary>
    public static RecentItems Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            var restored = JsonSerializer.Deserialize(text, RecentItemsJsonContext.Default.RecentItems);
            return restored?.Items is { } items ? new RecentItems(items.Take(Limit).ToList()) : Empty;
        }
        catch (JsonException)
        {
            return Empty;
        }
    }
}

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(RecentItems))]
internal sealed partial class RecentItemsJsonContext : JsonSerializerContext;
