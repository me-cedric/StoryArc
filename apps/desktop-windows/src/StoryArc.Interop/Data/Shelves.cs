using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StoryArc.Interop.Data;

public enum ShelfType
{
    /// <summary>A set: members have no order of their own.</summary>
    Collection,

    /// <summary>A reading list: entries in the order the reader keeps them.</summary>
    ReadingList,
}

/// <summary>
/// One collection or reading list as a screen reads it. Members are publication ids (the identity the library uses,
/// a path for a folder source). A shelf a server defines carries its source's id; the reader's own has none.
/// </summary>
public sealed record Shelf(
    ShelfType Kind,
    string Id,
    string Name,
    IReadOnlyList<string> Members,
    string? CoverMemberId,
    string? ServerSourceId)
{
    public bool IsLocal => ServerSourceId is null;

    internal static Shelf From(ShelfType kind, JsonNode node)
    {
        var members = (node[kind == ShelfType.Collection ? "members" : "entries"]?.AsArray() ?? new JsonArray())
            .Select(member => member!.GetValue<string>())
            .ToList();
        var origin = node["origin"];
        return new Shelf(
            kind,
            node["id"]?.GetValue<string>() ?? string.Empty,
            node["name"]?.GetValue<string>() ?? string.Empty,
            members,
            node["coverMemberId"]?.GetValue<string>(),
            origin?["kind"]?.GetValue<string>() == "server" ? origin["sourceId"]?.GetValue<string>() : null);
    }
}

/// <summary>Every collection and reading list, the reader's own and a server's, in one value the core's rules change.</summary>
public sealed class ShelvesState
{
    private ShelvesState(string json)
    {
        Json = json;
        var root = JsonNode.Parse(json);
        Collections = [.. (root?["collections"]?.AsArray() ?? new JsonArray()).Select(node => Shelf.From(ShelfType.Collection, node!))];
        Lists = [.. (root?["lists"]?.AsArray() ?? new JsonArray()).Select(node => Shelf.From(ShelfType.ReadingList, node!))];
    }

    public static ShelvesState Empty { get; } = new("""{"collections":[],"lists":[]}""");

    public string Json { get; }

    public IReadOnlyList<Shelf> Collections { get; }

    public IReadOnlyList<Shelf> Lists { get; }

    /// <summary>Collections, then reading lists, each in the order kept.</summary>
    public IEnumerable<Shelf> All => Collections.Concat(Lists);

    public Shelf? Find(string id) => All.FirstOrDefault(shelf => shelf.Id == id);

    internal static ShelvesState FromJson(string json) => new(json);

    /// <summary>The shelves the file held, or none for a file that is missing or damaged: a shelf is never worth a failed launch.</summary>
    public static ShelvesState Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            return ShelfRules.Apply(FromJson(text), []);
        }
        catch (Exception error) when (error is JsonException or StoryArcException or InvalidOperationException)
        {
            return Empty;
        }
    }

    public string Save() => Json;
}

/// <summary>One change to the shelves, in the shape the core's <c>storyarc_shelves_apply</c> takes.</summary>
public sealed record ShelfOp(JsonObject Node)
{
    private static ShelfOp Op(string name, params (string Key, JsonNode? Value)[] fields)
    {
        var node = new JsonObject { ["op"] = name };
        foreach (var (key, value) in fields)
        {
            node[key] = value;
        }

        return new ShelfOp(node);
    }

    private static JsonArray Strings(IEnumerable<string> items) => new(items.Select(item => (JsonNode?)item).ToArray());

    /// <summary>A new collection. The id is the core's own unless one is given (a test, or an import).</summary>
    public static ShelfOp CreateCollection(string name, string? id = null) => Op("createCollection", ("name", name), ("id", id));

    public static ShelfOp RenameCollection(string id, string name) => Op("renameCollection", ("id", id), ("name", name));

    public static ShelfOp AddMembers(string id, IEnumerable<string> members) => Op("addMembers", ("id", id), ("members", Strings(members)));

    public static ShelfOp RemoveMembers(string id, IEnumerable<string> members) => Op("removeMembers", ("id", id), ("members", Strings(members)));

    /// <summary>The cover a collection shows. <c>null</c> goes back to the first four available covers.</summary>
    public static ShelfOp SetCollectionCover(string id, string? member) => Op("setCollectionCover", ("id", id), ("member", member));

    public static ShelfOp DeleteCollection(string id) => Op("deleteCollection", ("id", id));

    public static ShelfOp CreateList(string name, string? id = null) => Op("createList", ("name", name), ("id", id));

    public static ShelfOp RenameList(string id, string name) => Op("renameList", ("id", id), ("name", name));

    public static ShelfOp Append(string id, IEnumerable<string> entries) => Op("append", ("id", id), ("entries", Strings(entries)));

    public static ShelfOp RemoveEntry(string id, string entry) => Op("removeEntry", ("id", id), ("entry", entry));

    public static ShelfOp MoveEntry(string id, string entry, int to) => Op("moveEntry", ("id", id), ("entry", entry), ("to", to));

    public static ShelfOp SetListCover(string id, string? member) => Op("setListCover", ("id", id), ("member", member));

    public static ShelfOp DeleteList(string id) => Op("deleteList", ("id", id));

    /// <summary>Forgets every shelf a removed source defined.</summary>
    public static ShelfOp RemoveSource(string sourceId) => Op("removeSource", ("sourceId", sourceId));
}

/// <summary>A server, one of its shelves, and which kind: none of the three names a shelf alone.</summary>
public sealed record ShelfKey(string SourceId, long ShelfId, ShelfType Kind)
{
    internal JsonObject ToNode() => new()
    {
        ["sourceID"] = SourceId,
        ["shelfID"] = ShelfId,
        ["kind"] = Kind == ShelfType.Collection ? "collection" : "list",
    };

    internal static ShelfKey From(JsonNode node) => new(
        node["sourceID"]?.GetValue<string>() ?? node["sourceId"]?.GetValue<string>() ?? string.Empty,
        node["shelfID"]?.GetValue<long>() ?? node["shelfId"]?.GetValue<long>() ?? 0,
        node["kind"]?.GetValue<string>() == "collection" ? ShelfType.Collection : ShelfType.ReadingList);
}

/// <summary>One addition to a server's shelf that the server has not seen yet. <see cref="Title"/> is what the pending row says, since the server cannot be asked.</summary>
public sealed record PendingShelfEdit(ShelfKey Shelf, string Entry, string Title, DateTimeOffset MadeAt)
{
    /// <summary>The same entry added to the same shelf twice is one pending edit.</summary>
    public string Id => string.Create(CultureInfo.InvariantCulture, $"{Shelf.SourceId}/{Shelf.Kind}/{Shelf.ShelfId}/{Entry}");

    internal JsonObject ToNode() => new()
    {
        ["shelf"] = Shelf.ToNode(),
        ["entry"] = Entry,
        ["title"] = Title,
        ["madeAt"] = MadeAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
    };

    internal static PendingShelfEdit From(JsonNode node) => new(
        ShelfKey.From(node["shelf"]!),
        node["entry"]?.GetValue<string>() ?? string.Empty,
        node["title"]?.GetValue<string>() ?? string.Empty,
        DateTimeOffset.Parse(node["madeAt"]?.GetValue<string>() ?? "1970-01-01T00:00:00Z", CultureInfo.InvariantCulture));
}

/// <summary>What a server shelf held the last time it answered.</summary>
public sealed record ShelfBaseline(ShelfKey Shelf, IReadOnlyList<string> Entries)
{
    internal JsonObject ToNode() => new() { ["shelf"] = Shelf.ToNode(), ["entries"] = new JsonArray(Entries.Select(entry => (JsonNode?)entry).ToArray()) };

    internal static ShelfBaseline From(JsonNode node) => new(
        ShelfKey.From(node["shelf"]!),
        [.. (node["entries"]?.AsArray() ?? new JsonArray()).Select(entry => entry!.GetValue<string>())]);
}

/// <summary>
/// The offline edit queue of the server shelves (storyarc-core <c>ShelfEditQueue</c>): what is owed to servers and what each
/// shelf held when it last answered. The core reconciles it (<see cref="ShelfRules.Pull"/>); queueing and forgetting an edit
/// are small enough that the core's seam leaves them to the host, so they live here, with the same behaviour: an edit for the
/// same entry on the same shelf replaces the earlier one.
/// </summary>
public sealed record ShelfEditQueue(IReadOnlyList<PendingShelfEdit> Edits, IReadOnlyList<ShelfBaseline> Baselines)
{
    public static ShelfEditQueue Empty { get; } = new([], []);

    public ShelfEditQueue Queueing(PendingShelfEdit edit) =>
        this with { Edits = [.. Edits.Where(existing => existing.Id != edit.Id), edit] };

    public ShelfEditQueue Dropping(IEnumerable<PendingShelfEdit> done)
    {
        var gone = done.Select(edit => edit.Id).ToHashSet();
        return this with { Edits = [.. Edits.Where(edit => !gone.Contains(edit.Id))] };
    }

    public ShelfEditQueue Recording(ShelfBaseline baseline) =>
        this with { Baselines = [.. Baselines.Where(existing => existing.Shelf != baseline.Shelf), baseline] };

    /// <summary>The edits owed to one shelf, oldest first.</summary>
    public IReadOnlyList<PendingShelfEdit> Pending(ShelfKey shelf) => [.. Edits.Where(edit => edit.Shelf == shelf).OrderBy(edit => edit.MadeAt)];

    /// <summary>Forgets everything a removed source defined.</summary>
    public ShelfEditQueue RemovingAllFrom(string sourceId) => new(
        [.. Edits.Where(edit => edit.Shelf.SourceId != sourceId)],
        [.. Baselines.Where(baseline => baseline.Shelf.SourceId != sourceId)]);

    internal JsonObject ToNode() => new()
    {
        ["edits"] = new JsonArray(Edits.Select(edit => (JsonNode?)edit.ToNode()).ToArray()),
        ["baselines"] = new JsonArray(Baselines.Select(baseline => (JsonNode?)baseline.ToNode()).ToArray()),
    };

    public string Save() => ToNode().ToJsonString();

    public static ShelfEditQueue Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            var root = JsonNode.Parse(text);
            return new ShelfEditQueue(
                [.. (root?["edits"]?.AsArray() ?? new JsonArray()).Select(node => PendingShelfEdit.From(node!))],
                [.. (root?["baselines"]?.AsArray() ?? new JsonArray()).Select(node => ShelfBaseline.From(node!))]);
        }
        catch (Exception error) when (error is JsonException or FormatException or InvalidOperationException)
        {
            return Empty;
        }
    }
}

/// <summary>What one server shelf holds now, from the server that answered.</summary>
public sealed record ShelfSnapshot(ShelfKey Shelf, IReadOnlyList<string> Entries);

/// <summary>One server shelf where edits were discarded because someone else changed it: the reader is told once what was dropped.</summary>
public sealed record ShelfConflict(ShelfKey Shelf, IReadOnlyList<PendingShelfEdit> Discarded);

/// <summary>What one round of reconciling the shelves that answered decided: what to send, what to forget, and what conflicted.</summary>
public sealed record ShelfPullResult(
    IReadOnlyList<PendingShelfEdit> ToPush,
    IReadOnlyList<PendingShelfEdit> ToDrop,
    IReadOnlyList<ShelfConflict> Conflicts);

/// <summary>A row of a server list as the reader sees it. A pending row is drawn in grey, after the server's own.</summary>
public sealed record ShelfRow(string Id, string Title, bool IsPending);

/// <summary>The shelf rules, run by the core across the seam.</summary>
public static unsafe class ShelfRules
{
    /// <summary>Applies <paramref name="ops"/> in order and answers the new shelves.</summary>
    public static ShelvesState Apply(ShelvesState shelves, IReadOnlyList<ShelfOp> ops) => Apply(shelves.Json, ops);

    internal static ShelvesState Apply(string shelvesJson, IReadOnlyList<ShelfOp> ops)
    {
        var request = new JsonObject
        {
            ["shelves"] = JsonNode.Parse(shelvesJson),
            ["ops"] = new JsonArray(ops.Select(op => op.Node.DeepClone()).ToArray()),
        };
        return ShelvesState.FromJson(NativeCore.CallJson(NativeMethods.storyarc_shelves_apply, "storyarc_shelves_apply", request.ToJsonString()));
    }

    /// <summary>
    /// Reconciles the offline edits with the shelves that answered. A shelf that did not answer is left out of
    /// <paramref name="remote"/> and left alone: an unreachable server is not a conflict.
    /// </summary>
    public static ShelfPullResult Pull(ShelfEditQueue queue, IReadOnlyList<ShelfSnapshot> remote)
    {
        var request = new JsonObject
        {
            ["queue"] = queue.ToNode(),
            ["remote"] = new JsonArray(remote.Select(snapshot => (JsonNode?)new JsonObject
            {
                ["shelf"] = snapshot.Shelf.ToNode(),
                ["entries"] = new JsonArray(snapshot.Entries.Select(entry => (JsonNode?)entry).ToArray()),
            }).ToArray()),
        };
        var answer = JsonNode.Parse(NativeCore.CallJson(NativeMethods.storyarc_shelf_pull, "storyarc_shelf_pull", request.ToJsonString()))
            ?? throw new JsonException("the core wrote a null shelf pull");
        static IReadOnlyList<PendingShelfEdit> Edits(JsonNode? list) =>
            [.. (list?.AsArray() ?? new JsonArray()).Select(edit => PendingShelfEdit.From(edit!))];
        return new ShelfPullResult(
            Edits(answer["toPush"]),
            Edits(answer["toDrop"]),
            [.. (answer["conflicts"]?.AsArray() ?? new JsonArray()).Select(conflict => new ShelfConflict(
                ShelfKey.From(conflict!["shelf"]!),
                Edits(conflict["discarded"])))]);
    }

    /// <summary>
    /// The list while edits wait: the server's entries in its order, then the outstanding ones, oldest first, marked
    /// pending. The core's <c>edits::projecting</c> is not exported over the seam, and the rule is one filter and a sort, so
    /// this mirrors it; <c>ShelfRulesTests</c> pins the same example the core's own test uses.
    /// </summary>
    public static IReadOnlyList<ShelfRow> Project(IReadOnlyList<ShelfRow> remote, IReadOnlyList<PendingShelfEdit> pending)
    {
        var held = remote.Select(row => row.Id).ToHashSet();
        var waiting = pending.Where(edit => !held.Contains(edit.Entry)).OrderBy(edit => edit.MadeAt);
        return [.. remote, .. waiting.Select(edit => new ShelfRow(edit.Entry, edit.Title, IsPending: true))];
    }
}
