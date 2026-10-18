using System.Text.Json;
using System.Text.Json.Serialization;

namespace StoryArc.Interop;

/// <summary>
/// How a publication is known across sources (ADR-0006), as the seam writes it: flat, camel case,
/// every field optional. A server identifier is a source id and a remote id together, never one alone.
/// </summary>
public sealed record CoreIdentity(
    string? ServerSourceId = null,
    string? ServerRemoteId = null,
    string? ContentDigest = null,
    string? NormalizedPath = null)
{
    /// <summary>The identity as the UTF-8 JSON object <c>storyarc_progress_read</c> takes.</summary>
    public string ToJson() => JsonSerializer.Serialize(this, CoreJsonContext.Default.CoreIdentity);
}

/// <summary>
/// One publication record, the JSON shape <c>storyarc_folder_records</c> and
/// <c>storyarc_publication_metadata</c> write (storyarc-core <c>domain::Publication</c>, the shape the
/// phones' library documents use). The enumerations stay strings, so a value a newer core adds
/// reads as text instead of failing the whole folder.
/// </summary>
/// <param name="Format">cbz, cbr, cb7, cbt, epub, pdf, imageFolder, m4b, mp3, flac, ogg or audioFolder.</param>
/// <param name="Number">Issue or chapter, as text: "3.5" and "Annual 1" are both real.</param>
/// <param name="ReadingDirection">leftToRight or rightToLeft.</param>
/// <param name="PageCount">Pages for a comic; absent when the core could not index that deep.</param>
public sealed record CorePublication(
    CoreIdentity Identity,
    string Format,
    string DisplayTitle,
    string? Series = null,
    string? Number = null,
    long? Volume = null,
    IReadOnlyList<string>? Authors = null,
    IReadOnlyList<string>? Pencillers = null,
    string? Publisher = null,
    long? Year = null,
    string? Language = null,
    string? Summary = null,
    IReadOnlyList<string>? Genres = null,
    IReadOnlyList<string>? Tags = null,
    string? Status = null,
    string? Origin = null,
    int? PageCount = null,
    int SkippedPageCount = 0,
    string? CoverPath = null,
    string ReadingDirection = "leftToRight",
    bool IsFixedLayout = false,
    string? SourceId = null,
    long? FileSize = null,
    DateTimeOffset? ModifiedAt = null,
    DateTimeOffset? AddedAt = null)
{
    [JsonIgnore]
    public bool IsRightToLeft => ReadingDirection == "rightToLeft";

    /// <summary>The records of a folder, from the JSON array the seam wrote.</summary>
    public static IReadOnlyList<CorePublication> ListFrom(string json) =>
        JsonSerializer.Deserialize(json, CoreJsonContext.Default.ListCorePublication) ?? [];

    /// <summary>One record, from the JSON object the seam wrote.</summary>
    public static CorePublication From(string json) =>
        JsonSerializer.Deserialize(json, CoreJsonContext.Default.CorePublication)
        ?? throw new JsonException("the core wrote a null publication record");
}

/// <summary>
/// Where a reader is: in a paged publication page <see cref="Index"/> (from zero) of <see cref="Of"/>; in a listened one
/// (<c>kind</c> "listening") part <see cref="Part"/> of <see cref="PartCount"/> at <see cref="OffsetMillis"/> into a part of
/// <see cref="OfMillis"/>, the shape both phones write. A field another kind does not carry reads as zero or null.
/// </summary>
public sealed record CorePosition(
    string Kind,
    int Index = 0,
    int Of = 0,
    int? Part = null,
    int? PartCount = null,
    long? OffsetMillis = null,
    long? OfMillis = null);

/// <summary>
/// A reading position, the JSON shape <c>storyarc_progress_write</c> takes and
/// <c>storyarc_progress_read</c> returns (storyarc-core <c>domain::ReadingProgress</c>).
/// </summary>
/// <param name="UpdatedAt">An RFC 3339 UTC moment, as the phones write it.</param>
public sealed record CoreProgress(CoreIdentity Identity, CorePosition Position, bool IsFinished, string UpdatedAt)
{
    /// <summary>
    /// The record of page <paramref name="index"/> (from zero) of <paramref name="pageCount"/>, read at
    /// <paramref name="at"/>. Reaching the last page finishes the publication, as on the phones.
    /// </summary>
    public static CoreProgress Page(CoreIdentity identity, int index, int pageCount, DateTimeOffset at) => new(
        identity,
        new CorePosition("page", index, pageCount),
        IsFinished: pageCount > 0 && index >= pageCount - 1,
        UpdatedAt: at.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture));

    /// <summary>
    /// The record of a single-file audiobook heard to <paramref name="offset"/> of <paramref name="duration"/>: part 0 of 1,
    /// as the phones write a file that is one part. Reaching the end finishes it.
    /// </summary>
    public static CoreProgress Listening(CoreIdentity identity, TimeSpan offset, TimeSpan duration, DateTimeOffset at) => new(
        identity,
        new CorePosition(
            "listening",
            Part: 0,
            PartCount: 1,
            OffsetMillis: (long)Math.Max(0, offset.TotalMilliseconds),
            OfMillis: duration > TimeSpan.Zero ? (long)duration.TotalMilliseconds : null),
        IsFinished: duration > TimeSpan.Zero && offset >= duration,
        UpdatedAt: at.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture));

    public string ToJson() => JsonSerializer.Serialize(this, CoreJsonContext.Default.CoreProgress);

    /// <summary>The record the store returned, or <c>null</c> for the JSON <c>null</c> it writes when there is none.</summary>
    public static CoreProgress? FromJson(string json) =>
        JsonSerializer.Deserialize(json, CoreJsonContext.Default.CoreProgress);

    /// <summary>0 to 1: how far through the publication the position is.</summary>
    [JsonIgnore]
    public double Fraction => IsFinished ? 1 : Position.Of <= 1 ? 0 : Math.Clamp((double)Position.Index / (Position.Of - 1), 0, 1);
}

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(CoreIdentity))]
[JsonSerializable(typeof(CorePublication))]
[JsonSerializable(typeof(List<CorePublication>))]
[JsonSerializable(typeof(CoreProgress))]
internal sealed partial class CoreJsonContext : JsonSerializerContext;
