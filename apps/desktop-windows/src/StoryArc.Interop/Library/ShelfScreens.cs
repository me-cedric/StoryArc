using StoryArc.Interop.Data;

namespace StoryArc.Interop.Library;

/// <summary>
/// The shelves the reader pinned, in the order they pinned them, as tokens (<c>collection:&lt;id&gt;</c> or <c>list:&lt;id&gt;</c>), the form the
/// library document carries and the phones read. Pinned shelves are what Home draws and what the sidebar lists first.
/// </summary>
public sealed record PinnedShelves(IReadOnlyList<string> Tokens)
{
    public static PinnedShelves None { get; } = new([]);

    /// <summary>The token of a shelf, which names its kind and its id.</summary>
    public static string TokenOf(Shelf shelf) => (shelf.Kind == ShelfType.Collection ? "collection:" : "list:") + shelf.Id;

    public bool IsPinned(Shelf shelf) => Tokens.Contains(TokenOf(shelf));

    /// <summary>Pinned last, so a shelf pinned later comes after the ones before it. Pinning twice changes nothing.</summary>
    public PinnedShelves Pinning(Shelf shelf) => IsPinned(shelf) ? this : new([.. Tokens, TokenOf(shelf)]);

    public PinnedShelves Unpinning(Shelf shelf) => new([.. Tokens.Where(token => token != TokenOf(shelf))]);

    /// <summary>Moves a pinned shelf to <paramref name="to"/> (clamped), which is how the reader reorders Home.</summary>
    public PinnedShelves Moving(Shelf shelf, int to)
    {
        var token = TokenOf(shelf);
        if (!Tokens.Contains(token))
        {
            return this;
        }

        var rest = Tokens.Where(existing => existing != token).ToList();
        rest.Insert(Math.Clamp(to, 0, rest.Count), token);
        return new PinnedShelves(rest);
    }

    /// <summary>A shelf that is gone leaves its pin behind in a document: forgotten here, so the list names only shelves that exist.</summary>
    public PinnedShelves Pruned(ShelvesState shelves)
    {
        var existing = shelves.All.Select(TokenOf).ToHashSet();
        return new PinnedShelves([.. Tokens.Where(existing.Contains)]);
    }

    /// <summary>The shelves with the pinned ones first, in the order pinned, then the rest by name: the sidebar's order.</summary>
    public IReadOnlyList<Shelf> Ordering(IEnumerable<Shelf> shelves)
    {
        var all = shelves.ToList();
        var pinned = Tokens.Select(token => all.FirstOrDefault(shelf => TokenOf(shelf) == token)).OfType<Shelf>();
        var rest = all.Where(shelf => !IsPinned(shelf)).OrderBy(shelf => shelf.Name, StringComparer.CurrentCultureIgnoreCase);
        return [.. pinned, .. rest];
    }
}

/// <summary>
/// The id a shelf holds for a publication: the core's stable identity (<c>path:</c> for a file, <c>srv:</c> for a server's, <c>sha:</c> for a
/// digest), the three prefixes the phones use, so a shelf made on a phone finds the same publication here. Mirrors
/// storyarc-core <c>PublicationIdentity::stable_id</c>; the seam does not export it.
/// </summary>
public static class ShelfMemberId
{
    public static string Of(CoreIdentity identity)
    {
        if (identity.NormalizedPath is { } path)
        {
            return "path:" + path;
        }

        if (identity.ServerSourceId is { } source && identity.ServerRemoteId is { } remote)
        {
            return $"srv:{source}:{remote}";
        }

        return identity.ContentDigest is { } digest ? "sha:" + digest : "path:";
    }

    public static string Of(LibraryRecord record) => record.Core is { } core ? Of(core.Identity) : "path:" + record.Id;
}

/// <summary>Which shelves hold a publication, for the checkmarks of Add to Shelf.</summary>
public static class ShelfMembership
{
    public static IReadOnlyList<Shelf> Containing(ShelvesState shelves, LibraryRecord record) =>
        [.. shelves.All.Where(shelf => shelf.Members.Contains(ShelfMemberId.Of(record)))];

    /// <summary>The operations that add every id of <paramref name="ids"/> to <paramref name="shelf"/>, in one change: Add to Shelf from a selection.</summary>
    public static ShelfOp Adding(Shelf shelf, IEnumerable<string> ids) =>
        shelf.Kind == ShelfType.Collection ? ShelfOp.AddMembers(shelf.Id, ids) : ShelfOp.Append(shelf.Id, ids);

    /// <summary>The operation that takes every id of <paramref name="ids"/> out of <paramref name="shelf"/>.</summary>
    public static IReadOnlyList<ShelfOp> Removing(Shelf shelf, IEnumerable<string> ids) =>
        shelf.Kind == ShelfType.Collection
            ? [ShelfOp.RemoveMembers(shelf.Id, ids)]
            : [.. ids.Select(id => ShelfOp.RemoveEntry(shelf.Id, id))];
}

/// <summary>
/// One row of a shelf's page. A member the library does not have now (its source is away, or it was removed) is shown in grey as not
/// available instead of dropped, so the shelf keeps its shape; a pending row is an addition to a server's list the server has not seen.
/// </summary>
public sealed record ShelfPageRow(string Id, string Title, LibraryRecord? Record, bool IsPending)
{
    public bool IsAvailable => Record is { IsUnreadable: false };
}

/// <summary>How far through a reading list the reader is: entries finished over those the library can report on, which leaves out an entry it has nothing about.</summary>
public sealed record ListProgress(int Finished, int Reported, string? NextId)
{
    public double Fraction => Reported == 0 ? 0 : (double)Finished / Reported;
}

/// <summary>A shelf's page: its rows in order, its progress for a list, and the covers its tile shows (desktop-clients task 3.23a).</summary>
public sealed record ShelfPageModel(Shelf Shelf, IReadOnlyList<ShelfPageRow> Rows, ListProgress? Progress, IReadOnlyList<string> CoverIds)
{
    /// <summary>The covers a shelf tile draws: the chosen one when it is available, otherwise the first four available members.</summary>
    public const int CompositeCovers = 4;

    /// <summary>
    /// The page of <paramref name="shelf"/> over <paramref name="library"/>. A collection lists its members by title; a reading list keeps the
    /// reader's order. <paramref name="pending"/> are the offline additions to a server list, shown after the server's own rows, marked pending.
    /// </summary>
    public static ShelfPageModel From(Shelf shelf, IEnumerable<LibraryRecord> library, IReadOnlyList<PendingShelfEdit>? pending = null)
    {
        var byId = library
            .GroupBy(record => ShelfMemberId.Of(record), StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);
        IEnumerable<string> ids = shelf.Members;
        var rows = ids
            .Select(id => byId.TryGetValue(id, out var record)
                ? new ShelfPageRow(id, record.Title, record, IsPending: false)
                : new ShelfPageRow(id, id, null, IsPending: false))
            .ToList();
        if (shelf.Kind == ShelfType.Collection)
        {
            rows = [.. rows.OrderBy(row => row.Title, StringComparer.CurrentCultureIgnoreCase)];
        }

        var projected = ShelfRules.Project([.. rows.Select(row => new ShelfRow(row.Id, row.Title, false))], pending ?? []);
        var all = rows.Concat(projected.Where(row => row.IsPending).Select(row => new ShelfPageRow(row.Id, row.Title, null, IsPending: true))).ToList();

        var progress = shelf.Kind == ShelfType.ReadingList ? ProgressOf(rows) : null;
        return new ShelfPageModel(shelf, all, progress, CoverIdsOf(shelf, rows));
    }

    /// <summary>The next entry after <paramref name="id"/> in list order, whatever its series or source, that the library can open.</summary>
    public string? NextAfter(string id)
    {
        var at = Rows.ToList().FindIndex(row => row.Id == id);
        return at < 0 ? null : Rows.Skip(at + 1).FirstOrDefault(row => row.IsAvailable && !row.IsPending)?.Id;
    }

    private static ListProgress ProgressOf(IReadOnlyList<ShelfPageRow> rows)
    {
        var reported = rows.Where(row => row.Record is not null).ToList();
        var finished = reported.Count(row => row.Record!.ReadingState == ReadingState.Finished);
        var next = reported.FirstOrDefault(row => row.Record!.ReadingState != ReadingState.Finished && row.IsAvailable)?.Id;
        return new ListProgress(finished, reported.Count, next);
    }

    private static IReadOnlyList<string> CoverIdsOf(Shelf shelf, IReadOnlyList<ShelfPageRow> rows)
    {
        var available = rows.Where(row => row.IsAvailable).Select(row => row.Id).ToList();
        if (shelf.CoverMemberId is { } chosen && available.Contains(chosen))
        {
            return [chosen];
        }

        return [.. available.Take(CompositeCovers)];
    }
}

/// <summary>What Home shows of the shelves: the pinned ones that have something on them, in the order pinned. An empty shelf takes no space.</summary>
public static class HomeShelfRows
{
    public static IReadOnlyList<ShelfPageModel> From(ShelvesState shelves, PinnedShelves pinned, IEnumerable<LibraryRecord> library)
    {
        var records = library.ToList();
        return [.. pinned.Ordering(shelves.All.Where(pinned.IsPinned))
            .Select(shelf => ShelfPageModel.From(shelf, records))
            .Where(page => page.Rows.Any(row => row.IsAvailable))];
    }
}
