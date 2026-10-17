using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Data;

/// <summary>
/// One source as a library document carries it: its id and name, its kind (<c>localFolder</c>, <c>networkShare</c>,
/// <c>opdsCatalog</c> or <c>kavitaServer</c>), the address with every secret removed, and whether this device holds
/// the credential. The credential itself never appears here.
/// </summary>
public sealed record DocumentSource(string Id, string DisplayName, string Kind, string? Locator, bool NeedsSignIn)
{
    internal JsonObject ToNode() => new()
    {
        ["id"] = Id,
        ["displayName"] = DisplayName,
        ["kind"] = Kind,
        ["locator"] = Locator,
        ["needsSignIn"] = NeedsSignIn,
    };
}

/// <summary>
/// What this device holds that a library document carries (storyarc-core <c>LibrarySnapshot</c>). The core's progress store
/// is read by identity over the seam and not listed, so the progress records arrive from the caller, which asks the store
/// for each publication the library knows. Settings and themes are left to the phones: an empty settings map changes none.
/// </summary>
public static class LibrarySnapshots
{
    public static string Build(
        IEnumerable<DocumentSource> sources,
        PinBook pins,
        ShelvesState shelves,
        IEnumerable<string> progressRecords)
    {
        var certificatePins = new JsonObject();
        foreach (var group in pins.All().GroupBy(pin => pin.Host))
        {
            certificatePins[group.Key] = new JsonArray(group.Select(pin => (JsonNode?)pin.Fingerprint).ToArray());
        }

        var snapshot = new JsonObject
        {
            ["sources"] = new JsonArray(sources.Select(source => (JsonNode?)source.ToNode()).ToArray()),
            ["certificatePins"] = certificatePins,
            ["shelves"] = JsonNode.Parse(shelves.Json),
            ["progress"] = new JsonArray(progressRecords.Select(record => JsonNode.Parse(record)).ToArray()),
        };
        return snapshot.ToJsonString();
    }
}

/// <summary>What a merge decided: the snapshot to keep, what conflicted, which pins and shelf members arrived, and which sources need a sign-in here.</summary>
public sealed record LibraryMerge(
    string SnapshotJson,
    int ConflictCount,
    IReadOnlyList<string> PinsAdded,
    IReadOnlyList<string> SourcesNeedingSignIn,
    IReadOnlyList<string> Copies)
{
    internal static LibraryMerge From(string json)
    {
        var node = JsonNode.Parse(json) ?? throw new JsonException("the core wrote a null merge");

        static IReadOnlyList<string> Strings(JsonNode? list) =>
            [.. (list?.AsArray() ?? new JsonArray()).Select(item => item!.ToString())];

        return new LibraryMerge(
            node["snapshot"]?.ToJsonString() ?? "{}",
            node["conflicts"]?.AsArray().Count ?? 0,
            Strings(node["pinsAdded"]),
            Strings(node["sourcesNeedingSignIn"]),
            Strings(node["copies"]));
    }

    /// <summary>The merged reading positions, one JSON record each, for the progress store to take.</summary>
    public IReadOnlyList<string> ProgressRecords() =>
        [.. (JsonNode.Parse(SnapshotJson)?["progress"]?.AsArray() ?? new JsonArray()).Select(record => record!.ToJsonString())];

    /// <summary>
    /// The sources the merged snapshot holds, as documents name them. A source another device added arrives here with its address
    /// and without any credential, so the app lists it as needing a sign-in.
    /// </summary>
    public IReadOnlyList<DocumentSource> Sources() =>
        [.. (JsonNode.Parse(SnapshotJson)?["sources"]?.AsArray() ?? new JsonArray()).Select(node => new DocumentSource(
            node!["id"]?.GetValue<string>() ?? string.Empty,
            node["displayName"]?.GetValue<string>() ?? string.Empty,
            node["kind"]?.GetValue<string>() ?? string.Empty,
            node["locator"]?.GetValue<string>(),
            node["needsSignIn"]?.GetValue<bool>() ?? false))];

    /// <summary>The merged shelves, for the shelves file.</summary>
    public ShelvesState Shelves() =>
        JsonNode.Parse(SnapshotJson)?["shelves"] is { } shelves ? ShelvesState.FromJson(shelves.ToJsonString()) : ShelvesState.Empty;

    /// <summary>The merged certificate pins.</summary>
    public IReadOnlyList<CertificatePin> Pins() =>
        JsonNode.Parse(SnapshotJson)?["certificatePins"] is JsonObject pins
            ? [.. pins.SelectMany(pair => pair.Value!.AsArray().Select(print => new CertificatePin(pair.Key, print!.GetValue<string>())))]
            : [];
}

/// <summary>The library document and its sync, over the core: import a phone's document, write one, and keep one in a folder.</summary>
public static unsafe class LibraryDocuments
{
    /// <summary>
    /// Merges <paramref name="document"/> into <paramref name="snapshotJson"/>: furthest position, shelf members united, deletions as
    /// tombstones. A document from a newer app is <see cref="StoryArcStatus.Unsupported"/> naming both versions.
    /// </summary>
    public static LibraryMerge Import(byte[] document, string snapshotJson, string device)
    {
        var snapshot = NativeCore.Utf8(snapshotJson);
        var name = NativeCore.Utf8(device);
        StoryArcBuffer buffer = default;
        int status;
        fixed (byte* documentData = document)
        fixed (byte* snapshotData = snapshot)
        fixed (byte* nameData = name)
        {
            status = NativeMethods.storyarc_library_import(
                documentData, (nuint)document.Length, snapshotData, (nuint)snapshot.Length, nameData, (nuint)name.Length, &buffer);
        }

        if (status != NativeMethods.STORYARC_OK)
        {
            var error = new StoryArcException("storyarc_library_import", (StoryArcStatus)status, NativeCore.LastError());
            NativeMethods.storyarc_buffer_free(buffer);
            throw error;
        }

        return LibraryMerge.From(NativeCore.TakeString(buffer));
    }

    /// <summary>
    /// The document this device writes, as text. Secrets are out of every address. With <paramref name="passphrase"/> and
    /// <paramref name="credentials"/> the credentials the reader asked to carry travel sealed under the passphrase, never in clear.
    /// </summary>
    public static string Export(
        string snapshotJson,
        string appVersion,
        string device,
        DateTimeOffset now,
        bool forSync = false,
        string? passphrase = null,
        IReadOnlyDictionary<string, string>? credentials = null)
    {
        var request = new JsonObject
        {
            ["snapshot"] = JsonNode.Parse(snapshotJson),
            ["appVersion"] = appVersion,
            ["device"] = device,
            ["now"] = now.ToUnixTimeSeconds(),
            ["forSync"] = forSync,
        };
        if (passphrase is not null && credentials is not null)
        {
            request["sealed"] = SealRequest(passphrase, credentials);
        }

        return NativeCore.CallJson(NativeMethods.storyarc_library_export, "storyarc_library_export", request.ToJsonString());
    }

    /// <summary>
    /// Merges with the sync document in <paramref name="folder"/> and writes it back over the version read. An unreachable folder
    /// is <see cref="StoryArcStatus.Unreachable"/>: grey, never red, and the app syncs when it returns. A document from a newer app
    /// is <see cref="StoryArcStatus.Unsupported"/>.
    /// </summary>
    public static LibraryMerge Sync(string folder, string device, string appVersion, DateTimeOffset now, string snapshotJson)
    {
        var request = new JsonObject
        {
            ["folder"] = folder,
            ["device"] = device,
            ["appVersion"] = appVersion,
            ["now"] = now.ToUnixTimeSeconds(),
            ["snapshot"] = JsonNode.Parse(snapshotJson),
        };
        return LibraryMerge.From(NativeCore.CallJson(NativeMethods.storyarc_library_sync, "storyarc_library_sync", request.ToJsonString()));
    }

    /// <summary>Seals credentials by source id under <paramref name="passphrase"/>: the <c>secrets</c> object a document carries.</summary>
    public static string SealCredentials(string passphrase, IReadOnlyDictionary<string, string> credentials) =>
        NativeCore.CallJson(NativeMethods.storyarc_secrets_seal, "storyarc_secrets_seal", SealRequest(passphrase, credentials).ToJsonString());

    /// <summary>
    /// Opens a document's sealed credentials, by source id, for the vault. A wrong passphrase is
    /// <see cref="StoryArcStatus.Unauthorized"/> and nothing opens.
    /// </summary>
    public static IReadOnlyDictionary<string, string> OpenCredentials(string passphrase, string sealedJson)
    {
        var request = new JsonObject { ["passphrase"] = passphrase, ["secrets"] = JsonNode.Parse(sealedJson) };
        var opened = JsonNode.Parse(NativeCore.CallJson(NativeMethods.storyarc_secrets_open, "storyarc_secrets_open", request.ToJsonString()))?.AsObject()
            ?? new JsonObject();
        return opened.ToDictionary(pair => pair.Key, pair => pair.Value!.GetValue<string>(), StringComparer.Ordinal);
    }

    private static JsonObject SealRequest(string passphrase, IReadOnlyDictionary<string, string> credentials)
    {
        var items = new JsonObject();
        foreach (var (id, text) in credentials)
        {
            items[id] = text;
        }

        return new JsonObject { ["passphrase"] = passphrase, ["secrets"] = items };
    }

    /// <summary>The text of a document as the file holds it, UTF-8 without a byte order mark.</summary>
    public static byte[] ToFileBytes(string document) => new UTF8Encoding(false).GetBytes(document);
}
