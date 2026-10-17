using System.Text.Json;
using System.Text.Json.Nodes;

namespace StoryArc.Interop.Network;

/// <summary>A link to another page of a catalogue: a shelf, an author, a series.</summary>
public sealed record OpdsSection(string Title = "", string Href = "", long? Count = null);

/// <summary>The file a catalogue entry offers to download, the one the core ranked best (EPUB, then comics, then PDF).</summary>
public sealed record OpdsAcquisition(string Href = "", string? MediaType = null, long? Length = null);

/// <summary>One publication in a catalogue page.</summary>
public sealed record OpdsEntry(
    string Id = "",
    string Title = "",
    IReadOnlyList<string>? Authors = null,
    string? Summary = null,
    string? Series = null,
    double? SeriesIndex = null,
    string? Updated = null,
    string? Cover = null,
    string? Thumbnail = null,
    OpdsAcquisition? Best = null,
    IReadOnlyList<string>? UnreadableFormats = null)
{
    /// <summary>Whether the entry offers a file the app can open. When it does not, the formats it does offer are named.</summary>
    public bool CanDownload => Best is not null;
}

/// <summary>A group of a page: a heading, its links and its entries, with a link to see more.</summary>
public sealed record OpdsGroup(
    string Title = "",
    IReadOnlyList<OpdsSection>? Navigation = null,
    IReadOnlyList<OpdsEntry>? Publications = null,
    string? More = null);

/// <summary>A filter the page offers.</summary>
public sealed record OpdsFacet(string? Group = null, string Title = "", string Href = "", long? Count = null, bool IsActive = false);

/// <summary>
/// A catalogue page as <c>storyarc_opds_feed</c> writes it, in either dialect. A catalogue without search
/// answers <see cref="LocalOnly"/>, and the app then filters the entries it already holds.
/// </summary>
public sealed record OpdsPage(
    string Title = "",
    string Dialect = "",
    IReadOnlyList<OpdsSection>? Navigation = null,
    IReadOnlyList<OpdsEntry>? Publications = null,
    IReadOnlyList<OpdsGroup>? Groups = null,
    IReadOnlyList<OpdsFacet>? Facets = null,
    string? Next = null,
    bool Searchable = false,
    bool LocalOnly = false);

/// <summary>
/// A catalogue request: the root, the page asked for (the root when <c>null</c>), search terms against that
/// page, and the one credential the root's own origin receives. The core sends it to that origin and never
/// writes it back.
/// </summary>
public sealed record OpdsRequest(
    string Root,
    string? Url = null,
    string? Search = null,
    string? Username = null,
    string? Password = null,
    string? Token = null)
{
    /// <summary>Never prints the password or the token: a record's own <c>ToString</c> would.</summary>
    public override string ToString() => "OpdsRequest { Root = " + Root + " }";

    internal string ToJson() => JsonText.Object(
        ("root", Root), ("url", Url), ("search", Search), ("username", Username), ("password", Password), ("token", Token));
}

/// <summary>A Kavita library.</summary>
public sealed record KavitaLibrary(long Id = 0, string Name = "");

/// <summary>A Kavita series with its reading totals.</summary>
public sealed record KavitaSeries(long Id = 0, string Name = "", long LibraryId = 0, long Pages = 0, long PagesRead = 0);

/// <summary>A Kavita chapter, which is Kavita's unit of progress.</summary>
public sealed record KavitaChapter(long Id = 0, string Number = "", string? Title = null, long Pages = 0, long PagesRead = 0);

/// <summary>A Kavita volume and its chapters.</summary>
public sealed record KavitaVolume(long Id = 0, long Number = 0, string? Name = null, IReadOnlyList<KavitaChapter>? Chapters = null);

public sealed unsafe partial class CoreHttp
{
    /// <summary>
    /// Fetches a catalogue page or runs a search. A refused sign-in or an untrusted certificate is
    /// <see cref="StoryArcStatus.Unauthorized"/>: <see cref="CertificateChallenge.TryParse"/> tells the two apart. A
    /// catalogue that does not answer is <see cref="StoryArcStatus.Unreachable"/>.
    /// </summary>
    public OpdsPage OpdsFeed(OpdsRequest request)
    {
        var json = Use(pointer => NativeCore.CallJson(NativeMethods.storyarc_opds_feed, (void*)pointer, "storyarc_opds_feed", request.ToJson()));
        return JsonSerializer.Deserialize(json, NetworkJsonContext.Default.OpdsPage)
            ?? throw new JsonException("the core wrote a null catalogue page");
    }

    /// <summary>Signs in to a Kavita server with its API key and answers the account's name. A refused key is <see cref="StoryArcStatus.Unauthorized"/>.</summary>
    public string KavitaConnect(string address, string apiKey)
    {
        var node = JsonNode.Parse(KavitaCall(address, apiKey, "connect"));
        return node?["username"]?.GetValue<string>() ?? string.Empty;
    }

    public IReadOnlyList<KavitaLibrary> KavitaLibraries(string address, string apiKey) =>
        JsonSerializer.Deserialize(KavitaCall(address, apiKey, "libraries"), NetworkJsonContext.Default.KavitaLibraryArray) ?? [];

    /// <summary>The series of one library, or of every library when <paramref name="library"/> is <c>null</c>.</summary>
    public IReadOnlyList<KavitaSeries> KavitaSeriesOf(string address, string apiKey, long? library = null) =>
        JsonSerializer.Deserialize(KavitaCall(address, apiKey, "series", ("library", library)), NetworkJsonContext.Default.KavitaSeriesArray) ?? [];

    public IReadOnlyList<KavitaVolume> KavitaVolumes(string address, string apiKey, long series) =>
        JsonSerializer.Deserialize(KavitaCall(address, apiKey, "volumes", ("series", series)), NetworkJsonContext.Default.KavitaVolumeArray) ?? [];

    /// <summary>The chapter a reader should continue with, or <c>null</c> when the series has none to offer.</summary>
    public KavitaChapter? KavitaContinuePoint(string address, string apiKey, long series) =>
        JsonSerializer.Deserialize(KavitaCall(address, apiKey, "continuePoint", ("series", series)), NetworkJsonContext.Default.KavitaChapter);

    private string KavitaCall(string address, string apiKey, string call, params (string Name, long? Value)[] arguments)
    {
        var fields = new List<(string, JsonNode?)> { ("address", address), ("apiKey", apiKey), ("call", call) };
        fields.AddRange(arguments.Select(argument => (argument.Name, argument.Value is { } value ? (JsonNode?)value : null)));
        var request = JsonText.Object([.. fields]);
        return Use(pointer => NativeCore.CallJson(NativeMethods.storyarc_kavita_call, (void*)pointer, "storyarc_kavita_call", request));
    }
}
