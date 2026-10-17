using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StoryArc.Interop.Network;

/// <summary>
/// One publication to download: where its file goes, the library id the queue knows it by, where the bytes
/// come from, and the one credential the source's own <see cref="Origin"/> receives. The credential is sent
/// to that origin alone and never written back.
/// </summary>
public sealed record DownloadRequest(
    string Folder,
    string Id,
    string Title,
    string Url,
    string? SeriesHint = null,
    string? Origin = null,
    string? Username = null,
    string? Password = null,
    string? Token = null)
{
    /// <summary>Never prints the password or the token.</summary>
    public override string ToString() => "DownloadRequest { Id = " + Id + " }";

    internal string ToJson() => JsonText.Object(
        ("folder", Folder), ("id", Id), ("title", Title), ("url", Url), ("seriesHint", SeriesHint),
        ("origin", Origin), ("username", Username), ("password", Password), ("token", Token));
}

/// <summary>Bytes received so far, and the total, or <c>null</c> when the server named none.</summary>
public readonly record struct DownloadProgress(ulong Received, long? Total)
{
    /// <summary>0 to 1, or <c>null</c> while the total is not known.</summary>
    public double? Fraction => Total is > 0 ? Math.Clamp((double)Received / Total.Value, 0, 1) : null;
}

/// <summary>How a transfer began, which the queue says on the row: from the start, from a kept partial file, or from the start again because the server would not continue.</summary>
public enum Resumption
{
    Fresh,
    Resumed,
    Restarted,
}

/// <summary>A download that landed verified: the file in place, how it began, its size and the publication's record.</summary>
public sealed record DownloadLanding(string Path, Resumption Resumption, ulong ResumedFrom, long Length, CorePublication? Publication);

public sealed unsafe partial class CoreHttp
{
    /// <summary>
    /// Downloads one publication, resuming a partial file with a range request, verifying it by indexing it and moving
    /// it into place. This blocks until the file lands or fails, on the calling thread, which also receives
    /// <paramref name="progress"/>: run it on <see cref="Task.Run(Action)"/> and use one client per download.
    /// A raised <paramref name="cancel"/> throws <see cref="StoryArcStatus.Cancelled"/> and keeps the partial file,
    /// which is how a quit pauses a download. Bytes that are not a publication throw
    /// <see cref="StoryArcStatus.Unreadable"/>, which the queue re-queues once.
    /// </summary>
    public DownloadLanding Fetch(DownloadRequest request, IProgress<DownloadProgress>? progress = null, CancelToken? cancel = null)
    {
        var state = new ProgressState(progress);
        var context = GCHandle.Alloc(state);
        var added = false;
        try
        {
            cancel?.DangerousAddRef(ref added);
            var token = added ? cancel!.DangerousGetHandle() : IntPtr.Zero;
            var json = Use(pointer => FetchJson((void*)pointer, request.ToJson(), (void*)token, GCHandle.ToIntPtr(context)));
            return Landing(json);
        }
        finally
        {
            if (added)
            {
                cancel!.DangerousRelease();
            }

            context.Free();
        }
    }

    private static string FetchJson(void* http, string request, void* cancel, nint context)
    {
        var bytes = NativeCore.Utf8(request);
        StoryArcBuffer buffer = default;
        int status;
        try
        {
            fixed (byte* data = bytes)
            {
                status = NativeMethods.storyarc_download_fetch(
                    http, data, (nuint)bytes.Length, cancel, &OnProgress, (void*)context, &buffer);
            }
        }
        finally
        {
            System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes);
        }

        if (status != NativeMethods.STORYARC_OK)
        {
            var error = new StoryArcException("storyarc_download_fetch", (StoryArcStatus)status, NativeCore.LastError());
            NativeMethods.storyarc_buffer_free(buffer);
            throw error;
        }

        return NativeCore.TakeString(buffer);
    }

    /// <summary>
    /// The core's progress callback (<c>void (*)(void *context, uint64_t received, int64_t total)</c>), called on the
    /// calling thread. A managed exception must never cross into the core, so a reader's handler that throws loses
    /// that one report and nothing else.
    /// </summary>
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnProgress(void* context, ulong received, long total)
    {
        try
        {
            if (GCHandle.FromIntPtr((nint)context).Target is ProgressState state)
            {
                state.Report(new DownloadProgress(received, total < 0 ? null : total));
            }
        }
        catch (Exception)
        {
            // See above: dropped on purpose, the transfer goes on.
        }
    }

    private static DownloadLanding Landing(string json)
    {
        var node = JsonNode.Parse(json) ?? throw new JsonException("the core wrote a null landing");
        var (resumption, from) = ResumptionOf(node["resumption"]);
        var publication = node["publication"] is { } record
            ? JsonSerializer.Deserialize(record.ToJsonString(), CoreJsonContext.Default.CorePublication)
            : null;
        return new DownloadLanding(
            node["path"]?.GetValue<string>() ?? string.Empty,
            resumption,
            from,
            node["length"]?.GetValue<long>() ?? 0,
            publication);
    }

    /// <summary>The core writes <c>"fresh"</c>, <c>"restarted"</c> or <c>{"resumed":{"from":N}}</c> (serde's shape for the three cases).</summary>
    internal static (Resumption Resumption, ulong From) ResumptionOf(JsonNode? node) => node switch
    {
        JsonObject resumed when resumed["resumed"] is JsonObject inner => (Resumption.Resumed, inner["from"]?.GetValue<ulong>() ?? 0),
        JsonValue text when text.GetValue<string>() == "restarted" => (Resumption.Restarted, 0),
        _ => (Resumption.Fresh, 0),
    };

    private sealed class ProgressState(IProgress<DownloadProgress>? progress)
    {
        public void Report(DownloadProgress value) => progress?.Report(value);
    }
}
