using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Data;

/// <summary>
/// Where a download stands in the core's queue. <see cref="Running"/> is a state the core knows and the seam has no operation to
/// set (<c>marking</c> is not exported), so a row the app is transferring stays <see cref="Queued"/> here and the app's
/// coordinator, which owns the transfers, says which rows are active.
/// </summary>
public enum DownloadStatus
{
    Queued,
    Running,
    Paused,
    Failed,
    Finished,
}

/// <summary>
/// One row of the queue as the screen reads it. <see cref="Pause"/> is the core's reason for a paused row
/// (<c>byReader</c>, <c>waitingForUnmetered</c>, <c>waitingForNetwork</c> or <c>outOfSpace</c>); <see cref="FailureKind"/>
/// is a case, never a sentence, so the app words it in the reader's language on the day it is drawn.
/// </summary>
public sealed record DownloadRow(
    string Id,
    string Title,
    string Remote,
    string? SourceId,
    DownloadStatus Status,
    string? Pause,
    string? FailureKind,
    string? FailureDetail,
    int Attempts,
    long? ExpectedBytes,
    long DownloadedBytes,
    long? CompletedAt,
    bool StartedByHand,
    int VerificationFailures,
    Resumption? LastAttempt)
{
    /// <summary>0 to 1 while the size is known.</summary>
    public double? Fraction => ExpectedBytes is > 0 ? Math.Clamp((double)DownloadedBytes / ExpectedBytes.Value, 0, 1) : null;

    internal static DownloadRow From(JsonNode row)
    {
        var state = row["state"]?.AsObject() ?? new JsonObject();
        var tag = state["state"]?.GetValue<string>() ?? "queued";
        var status = tag switch
        {
            "running" => DownloadStatus.Running,
            "paused" => DownloadStatus.Paused,
            "failed" => DownloadStatus.Failed,
            "finished" => DownloadStatus.Finished,
            _ => DownloadStatus.Queued,
        };

        // serde writes a paused row's reason as the name of a key holding null beside the "state" tag.
        var pause = status == DownloadStatus.Paused ? state.Select(pair => pair.Key).FirstOrDefault(key => key != "state") : null;
        var reason = state["reason"];
        Resumption? last = row["lastAttempt"] is { } attempt ? CoreHttp.ResumptionOf(attempt).Resumption : null;
        return new DownloadRow(
            row["id"]?.GetValue<string>() ?? string.Empty,
            row["title"]?.GetValue<string>() ?? string.Empty,
            row["remote"]?.GetValue<string>() ?? string.Empty,
            row["sourceId"]?.GetValue<string>(),
            status,
            pause,
            reason?["kind"]?.GetValue<string>(),
            reason?["detail"]?.ToString(),
            state["attempts"]?.GetValue<int>() ?? 0,
            row["expectedBytes"]?.GetValue<long>(),
            row["downloadedBytes"]?.GetValue<long>() ?? 0,
            row["completedAt"]?.GetValue<long>(),
            row["startedByHand"]?.GetValue<bool>() ?? false,
            row["verificationFailures"]?.GetValue<int>() ?? 0,
            last);
    }
}

/// <summary>
/// The reader's download settings that decide admission (storyarc-core <c>DownloadPolicy</c>): "Wi-Fi only", which on a
/// desktop means over an unmetered connection only, how many run at once on each kind of connection, and an
/// optional limit on what the downloads folder may hold.
/// </summary>
public sealed record DownloadPolicySettings(
    bool UnmeteredOnly = true,
    int Concurrency = 3,
    int MeteredConcurrency = 1,
    long? StorageLimit = null)
{
    /// <summary>
    /// How many transfers may run at once on <paramref name="network"/>: the core's own bound (<c>DownloadPolicy::concurrency</c>), which the
    /// seam applies to the queue's running rows. Rows in flight are not marked running over the seam, so the host subtracts them
    /// itself, and a test holds this to the number <c>startable</c> answers.
    /// </summary>
    public int ConcurrencyFor(ConnectionState network)
    {
        var upper = Math.Max(Concurrency, 1);
        return network switch
        {
            ConnectionState.Unmetered => upper,
            ConnectionState.Metered => Math.Clamp(MeteredConcurrency, 1, upper),
            _ => 0,
        };
    }

    internal JsonObject ToNode() => new()
    {
        ["unmeteredOnly"] = UnmeteredOnly,
        ["concurrency"] = Concurrency,
        ["meteredConcurrency"] = MeteredConcurrency,
        ["storageLimit"] = StorageLimit,
    };
}

/// <summary>Why a download failed, as the core's cases.</summary>
public sealed record QueueFailure(string Kind, JsonNode? Detail = null)
{
    public static QueueFailure Network { get; } = new("network");

    public static QueueFailure Disk { get; } = new("disk");

    public static QueueFailure Unreadable { get; } = new("unreadable");

    public static QueueFailure Server(int status) => new("server", status);

    public static QueueFailure Unsupported(string format) => new("unsupported", format);

    /// <summary>The failure a seam status stands for, so a download that throws is filed under the right case.</summary>
    public static QueueFailure Of(StoryArcException error) => error.Status switch
    {
        StoryArcStatus.Storage => Disk,
        StoryArcStatus.Unreadable => Unreadable,
        StoryArcStatus.Unsupported => Unsupported(error.CoreMessage ?? "unknown"),
        StoryArcStatus.NotFound => Server(404),
        StoryArcStatus.Unauthorized => Server(401),
        _ => Network,
    };

    internal JsonObject ToNode()
    {
        var node = new JsonObject { ["kind"] = Kind };
        if (Detail is not null)
        {
            node["detail"] = Detail.DeepClone();
        }

        return node;
    }
}

/// <summary>One change to the queue, in the shape the core's <c>storyarc_queue_apply</c> takes.</summary>
public sealed record QueueOp(JsonObject Node)
{
    private static QueueOp Op(string name, params (string Key, JsonNode? Value)[] fields)
    {
        var node = new JsonObject { ["op"] = name };
        foreach (var (key, value) in fields)
        {
            node[key] = value;
        }

        return new QueueOp(node);
    }

    /// <summary>Adds a publication the reader asked to keep. <paramref name="startedByHand"/> overrides "Wi-Fi only" once.</summary>
    public static QueueOp Queue(string id, string title, string remote, string? sourceId = null, long? expectedBytes = null, bool startedByHand = false) =>
        Op("queue", ("download", new JsonObject
        {
            ["id"] = id,
            ["title"] = title,
            ["remote"] = remote,
            ["sourceId"] = sourceId,
            ["expectedBytes"] = expectedBytes,
            ["startedByHand"] = startedByHand,
            ["state"] = new JsonObject { ["state"] = "queued" },
        }));

    public static QueueOp Pause(string id) => Op("pause", ("id", id));

    public static QueueOp Resume(string id) => Op("resume", ("id", id));

    public static QueueOp PauseAll() => Op("pauseAll");

    public static QueueOp ResumeAll() => Op("resumeAll");

    public static QueueOp Remove(string id) => Op("remove", ("id", id));

    public static QueueOp Move(string id, int to) => Op("move", ("id", id), ("to", to));

    /// <summary>A transfer moved: the row runs, with the bytes so far and the size when the server named one.</summary>
    public static QueueOp Advance(string id, long downloaded, long? expected) =>
        Op("advance", ("id", id), ("downloaded", downloaded), ("expected", expected));

    public static QueueOp Fail(string id, QueueFailure reason, bool retryable) =>
        Op("fail", ("id", id), ("reason", reason.ToNode()), ("retryable", retryable));

    /// <summary>The bytes arrived and are not a publication: re-queued once, then failed.</summary>
    public static QueueOp FailVerification(string id, QueueFailure reason) =>
        Op("failVerification", ("id", id), ("reason", reason.ToNode()));

    public static QueueOp Finish(string id, long bytes, DateTimeOffset at) =>
        Op("finish", ("id", id), ("bytes", bytes), ("at", at.ToUnixTimeMilliseconds()));

    /// <summary>
    /// The connection or the policy changed: pauses what the policy holds back, running rows included, and releases
    /// what it no longer holds. <paramref name="used"/> is what the downloads folder holds now.
    /// </summary>
    public static QueueOp Hold(ConnectionState network, DownloadPolicySettings policy, long used) =>
        Op("hold", ("network", NetworkName(network)), ("policy", policy.ToNode()), ("used", used));

    /// <summary>A row that was running when the app was killed comes back queued.</summary>
    public static QueueOp Reclaim() => Op("reclaim");

    internal static string NetworkName(ConnectionState network) => network switch
    {
        ConnectionState.Metered => "metered",
        ConnectionState.Offline => "offline",
        _ => "unmetered",
    };
}

/// <summary>Seconds to wait before a failed row is tried again: three attempts, doubling from two seconds.</summary>
public sealed record RetryAfter(string Id, int Seconds);

/// <summary>
/// The queue's state and the answer to one <see cref="DownloadQueues.Apply"/>: the new queue, the ids that may start
/// now (when a connection and a policy were given), and the failed rows to try again with their wait.
/// </summary>
public sealed record QueueOutcome(DownloadQueue Queue, IReadOnlyList<string> Startable, IReadOnlyList<RetryAfter> Retry);

/// <summary>
/// Every download in the reader's order. The core owns the rules (admission, pausing, the retry bound, the
/// verification re-queue); C# keeps the value and saves it. A queue holds no credential: a row's <c>remote</c> is
/// an address the source signs the request for, so the file is plain JSON.
/// </summary>
public sealed class DownloadQueue
{
    private DownloadQueue(string json)
    {
        Json = json;
        var rows = JsonNode.Parse(json)?["downloads"]?.AsArray() ?? new JsonArray();
        Rows = [.. rows.Where(row => row is not null).Select(row => DownloadRow.From(row!))];
    }

    public static DownloadQueue Empty { get; } = new("""{"downloads":[]}""");

    public string Json { get; }

    public IReadOnlyList<DownloadRow> Rows { get; }

    public DownloadRow? Get(string id) => Rows.FirstOrDefault(row => row.Id == id);

    /// <summary>Whether any row is still to do: the queue says "waiting" in grey, and quitting asks first when one is running.</summary>
    public bool HasPending => Rows.Any(row => row.Status != DownloadStatus.Finished);

    internal static DownloadQueue FromJson(string json) => new(json);

    /// <summary>The queue the file held, with a row that was running at a kill put back to queued, or an empty queue for a file that is missing or damaged.</summary>
    public static DownloadQueue Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            return DownloadQueues.Apply(FromJson(text), [QueueOp.Reclaim()]).Queue;
        }
        catch (Exception error) when (error is JsonException or StoryArcException or InvalidOperationException)
        {
            return Empty;
        }
    }

    public string Save() => Json;
}

/// <summary>The queue's rules, run by the core across the seam.</summary>
public static unsafe class DownloadQueues
{
    /// <summary>
    /// Applies <paramref name="ops"/> in order. With <paramref name="network"/> and <paramref name="policy"/> the answer also
    /// names the rows that may start now, within the connection's bound.
    /// </summary>
    public static QueueOutcome Apply(
        DownloadQueue queue,
        IReadOnlyList<QueueOp> ops,
        ConnectionState? network = null,
        DownloadPolicySettings? policy = null)
    {
        var request = new JsonObject
        {
            ["queue"] = JsonNode.Parse(queue.Json),
            ["ops"] = new JsonArray(ops.Select(op => op.Node.DeepClone()).ToArray()),
        };
        if (network is { } connection)
        {
            request["startable"] = new JsonArray(QueueOp.NetworkName(connection), (policy ?? new DownloadPolicySettings()).ToNode());
        }

        var json = NativeCore.CallJson(NativeMethods.storyarc_queue_apply, "storyarc_queue_apply", request.ToJsonString());
        var answer = JsonNode.Parse(json) ?? throw new JsonException("the core wrote a null queue");
        var startable = answer["startable"]?.AsArray().Select(id => id!.GetValue<string>()).ToList() ?? [];
        var retry = answer["retry"]?.AsArray()
            .Select(pair => new RetryAfter(pair![0]!.GetValue<string>(), checked((int)pair[1]!.GetValue<long>())))
            .ToList() ?? [];
        return new QueueOutcome(DownloadQueue.FromJson(answer["queue"]!.ToJsonString()), startable, retry);
    }

    /// <summary>A size as a reader reads it, in the current culture: "12.4 MB".</summary>
    public static string Size(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var value = (double)bytes;
        var unit = 0;
        while (value >= 1000 && unit < units.Length - 1)
        {
            value /= 1000;
            unit++;
        }

        return unit == 0
            ? string.Create(CultureInfo.CurrentCulture, $"{bytes} B")
            : string.Create(CultureInfo.CurrentCulture, $"{value:0.#} {units[unit]}");
    }
}
