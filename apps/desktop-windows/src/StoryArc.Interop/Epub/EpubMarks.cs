using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Epub;

/// <summary>The highlight colours of the phones' <c>HighlightColour</c>; the lower-case name is the CSS tint the renderer draws.</summary>
public enum HighlightColour
{
    Yellow,
    Green,
    Blue,
    Pink,
    Purple,
}

/// <summary>A bookmark in an EPUB: the locator, its chapter's resource and progression, the chapter's name and an excerpt.</summary>
public sealed record EpubBookmark(string Id, string Locator, string Href, double Progression, string Chapter, string Excerpt, DateTimeOffset CreatedAt);

/// <summary>A highlight, with or without a note: one record for both, as on the phones.</summary>
public sealed record EpubHighlight(string Id, string Locator, string Href, double Progression, string Chapter, string Text, HighlightColour Colour, string Note, DateTimeOffset CreatedAt);

/// <summary>What a marks file holds for one publication.</summary>
public sealed record EpubMarksFile(IReadOnlyList<EpubBookmark> Bookmarks, IReadOnlyList<EpubHighlight> Highlights);

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, UseStringEnumConverter = true)]
[JsonSerializable(typeof(EpubMarksFile))]
internal sealed partial class EpubMarksJsonContext : JsonSerializerContext;

/// <summary>Where a locator points: the resource without its fragment, and the progression within it.</summary>
public readonly record struct EpubPlace(string Href, double Progression, double TotalProgression)
{
    public static EpubPlace Of(string? locatorJson)
    {
        if (locatorJson is null || Parse(locatorJson) is not JsonObject locator)
        {
            return new EpubPlace(string.Empty, 0, 0);
        }

        var href = locator["href"] is JsonValue h && h.TryGetValue<string>(out var text) ? text.Split('#')[0] : string.Empty;
        var locations = locator["locations"] as JsonObject;
        return new EpubPlace(href, Number(locations?["progression"]), Number(locations?["totalProgression"]));
    }

    internal static JsonNode? Parse(string json)
    {
        try
        {
            return JsonNode.Parse(json);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static double Number(JsonNode? node) => node is JsonValue value && value.TryGetValue<double>(out var number) ? number : 0;
}

/// <summary>
/// The reader's bookmarks and highlights in one EPUB (<c>ebook-reader</c>, "Bookmarks", "Highlights and notes"),
/// kept in a JSON file of the publication's own and listed in reading order. The file is read and written through
/// delegates so the store tests on any host; a write that fails keeps the marks for this session.
/// </summary>
public sealed class EpubMarks
{
    /// <summary>The decoration of the sentence the voice speaks: never a reader's highlight, so activating it opens nothing.</summary>
    public const string SpokenId = "spoken";

    /// <summary>Its tint, apart from the five highlight colours.</summary>
    public const string SpokenTint = "lightskyblue";

    private readonly Action<string> _write;
    private readonly Func<string, int> _orderOf;
    private List<EpubBookmark> _bookmarks;
    private List<EpubHighlight> _highlights;

    /// <param name="read">The file's text, or <c>null</c> when there is none.</param>
    /// <param name="write">Writes the file's new text.</param>
    /// <param name="orderOf">The reading-order index of a resource, so marks list in reading order.</param>
    public EpubMarks(Func<string?> read, Action<string> write, Func<string, int> orderOf)
    {
        _write = write;
        _orderOf = orderOf;
        var file = Restore(read());
        _bookmarks = [.. file.Bookmarks];
        _highlights = [.. file.Highlights];
    }

    public IReadOnlyList<EpubBookmark> Bookmarks => [.. _bookmarks.OrderBy(mark => _orderOf(mark.Href)).ThenBy(mark => mark.Progression)];

    public IReadOnlyList<EpubHighlight> Highlights => [.. _highlights.OrderBy(mark => _orderOf(mark.Href)).ThenBy(mark => mark.Progression)];

    /// <summary>The bookmark on the page a locator names, if there is one.</summary>
    public EpubBookmark? BookmarkAt(string locatorJson)
    {
        var place = EpubPlace.Of(locatorJson);
        return _bookmarks.FirstOrDefault(mark => mark.Href == place.Href && Math.Abs(mark.Progression - place.Progression) < 0.001);
    }

    /// <summary>Adds a bookmark at the page, or removes the one already there. Answers whether the page is now marked.</summary>
    public bool ToggleBookmark(string locatorJson, string chapter, string excerpt, DateTimeOffset now)
    {
        if (BookmarkAt(locatorJson) is { } existing)
        {
            _ = _bookmarks.Remove(existing);
            Save();
            return false;
        }

        var place = EpubPlace.Of(locatorJson);
        _bookmarks.Add(new EpubBookmark(Guid.NewGuid().ToString("D"), locatorJson, place.Href, place.Progression, chapter, excerpt, now));
        Save();
        return true;
    }

    public void RemoveBookmark(string id)
    {
        if (_bookmarks.RemoveAll(mark => mark.Id == id) > 0)
        {
            Save();
        }
    }

    /// <summary>Turns a selection into a highlight in the colour chosen.</summary>
    public EpubHighlight AddHighlight(EpubSelection selection, HighlightColour colour, string chapter, DateTimeOffset now)
    {
        var place = EpubPlace.Of(selection.Locator);
        var highlight = new EpubHighlight(Guid.NewGuid().ToString("D"), selection.Locator, place.Href, place.Progression, chapter, selection.Text, colour, string.Empty, now);
        _highlights.Add(highlight);
        Save();
        return highlight;
    }

    /// <summary>Writes a note on a highlight; an empty note removes the note and keeps the highlight.</summary>
    public void SetNote(string id, string note)
    {
        var index = _highlights.FindIndex(mark => mark.Id == id);
        if (index >= 0)
        {
            _highlights[index] = _highlights[index] with { Note = note.Trim() };
            Save();
        }
    }

    public void RemoveHighlight(string id)
    {
        if (_highlights.RemoveAll(mark => mark.Id == id) > 0)
        {
            Save();
        }
    }

    public EpubHighlight? Highlight(string id) => _highlights.FirstOrDefault(mark => mark.Id == id);

    /// <summary>The items of a <c>highlights</c> message: every highlight, and the spoken sentence as one more decoration in its own tint.</summary>
    public JsonArray HighlightItems(string? spokenLocatorJson = null)
    {
        var items = new JsonArray();
        foreach (var mark in _highlights)
        {
            if (EpubPlace.Parse(mark.Locator) is { } locator)
            {
                items.Add((JsonNode)new JsonObject { ["id"] = mark.Id, ["locator"] = locator, ["color"] = Tint(mark.Colour) });
            }
        }

        if (spokenLocatorJson is not null && EpubPlace.Parse(spokenLocatorJson) is { } spoken)
        {
            items.Add((JsonNode)new JsonObject { ["id"] = SpokenId, ["locator"] = spoken, ["color"] = SpokenTint });
        }

        return items;
    }

    /// <summary>A sentence of a chapter as a locator the renderer finds again by its text: the spoken sentence's place.</summary>
    public static string SpokenLocator(string sentence, string href) => new JsonObject
    {
        ["href"] = href.Split('#')[0],
        ["type"] = "application/xhtml+xml",
        ["locations"] = new JsonObject(),
        ["text"] = new JsonObject { ["highlight"] = sentence },
    }.ToJsonString();

    /// <summary>The CSS tint of a colour.</summary>
    public static string Tint(HighlightColour colour) => colour.ToString().ToLowerInvariant();

    /// <summary>
    /// The highlights and notes as one document, plain text or Markdown (<c>ebook-reader</c>, "Highlights and notes":
    /// "exportable as plain text or Markdown"): the book's title, then each passage under its chapter with its note.
    /// </summary>
    public string Export(string title, bool markdown)
    {
        var text = new StringBuilder();
        _ = text.Append(markdown ? "# " : string.Empty).Append(title).Append('\n');
        string? chapter = null;
        foreach (var mark in Highlights)
        {
            if (mark.Chapter != chapter)
            {
                chapter = mark.Chapter;
                _ = text.Append('\n').Append(markdown ? "## " : string.Empty).Append(chapter).Append('\n');
            }

            _ = text.Append('\n').Append(markdown ? "> " + mark.Text.ReplaceLineEndings(" ") : "“" + mark.Text + "”").Append('\n');
            if (mark.Note.Length > 0)
            {
                _ = text.Append(markdown ? "\n" : string.Empty).Append(mark.Note).Append('\n');
            }
        }

        return text.ToString();
    }

    /// <summary>
    /// An excerpt for a bookmark: the sentence of the chapter at <paramref name="progression"/>, shortened to a line,
    /// since the renderer's locator carries no text of its own.
    /// </summary>
    public static string ExcerptAt(IReadOnlyList<string> sentences, double progression)
    {
        if (sentences.Count == 0)
        {
            return string.Empty;
        }

        var sentence = sentences[Math.Clamp((int)(Math.Clamp(progression, 0, 1) * sentences.Count), 0, sentences.Count - 1)].Trim();
        return sentence.Length <= 120 ? sentence : sentence[..119].TrimEnd() + "…";
    }

    private void Save()
    {
        try
        {
            _write(JsonSerializer.Serialize(new EpubMarksFile(_bookmarks, _highlights), EpubMarksJsonContext.Default.EpubMarksFile));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Kept for this session; the next change tries again.
        }
    }

    private static EpubMarksFile Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return new EpubMarksFile([], []);
        }

        try
        {
            var file = JsonSerializer.Deserialize(text, EpubMarksJsonContext.Default.EpubMarksFile);
            return new EpubMarksFile(file?.Bookmarks ?? [], file?.Highlights ?? []);
        }
        catch (JsonException)
        {
            return new EpubMarksFile([], []);
        }
    }
}

/// <summary>What the reader chose with the pointer, waiting to become a highlight.</summary>
public sealed record EpubSelection(string Text, string Locator);

/// <summary>A note the book points to, shown where the reader is rather than by leaving the page.</summary>
public sealed record EpubFootnote(string Href, string Text);

/// <summary>One search result: the chapter, the match with its context, and the locator to go to.</summary>
public sealed record EpubSearchHit(string? Chapter, string Before, string Match, string After, string Locator);

/// <summary>One entry of the table of contents, flattened with its depth, and the locator that goes to it.</summary>
public sealed record EpubContentsEntry(string Title, string Href, int Depth, string Locator);

/// <summary>The publication's own navigation, from the manifest's <c>toc</c>, to its full depth.</summary>
public static class EpubContents
{
    public static IReadOnlyList<EpubContentsEntry> Of(string manifestJson)
    {
        var entries = new List<EpubContentsEntry>();
        if (EpubPlace.Parse(manifestJson) is JsonObject manifest && manifest["toc"] is JsonArray toc)
        {
            Walk(toc, 0, entries);
        }

        return entries;
    }

    /// <summary>The entry of the chapter being read: the first one on the resource the reader is in, or -1.</summary>
    public static int CurrentIndex(IReadOnlyList<EpubContentsEntry> entries, string? locatorJson)
    {
        var href = EpubPlace.Of(locatorJson).Href;
        for (var i = 0; i < entries.Count; i++)
        {
            if (entries[i].Href.Split('#')[0] == href)
            {
                return i;
            }
        }

        return -1;
    }

    /// <summary>The title of the chapter at a locator, or <c>null</c> when the book names none for it.</summary>
    public static string? ChapterTitle(IReadOnlyList<EpubContentsEntry> entries, string? locatorJson) =>
        CurrentIndex(entries, locatorJson) is var index and >= 0 ? entries[index].Title : null;

    /// <summary>A locator for a link of the manifest: its href and type, no location, so the renderer opens it at its start.</summary>
    public static string LocatorFor(string href, string? type = null) =>
        new JsonObject { ["href"] = href, ["type"] = type ?? "application/xhtml+xml", ["locations"] = new JsonObject() }.ToJsonString();

    private static void Walk(JsonArray links, int depth, List<EpubContentsEntry> entries)
    {
        foreach (var node in links)
        {
            if (node is not JsonObject link || link["href"] is not JsonValue hrefValue || !hrefValue.TryGetValue<string>(out var href) || href.Length == 0)
            {
                continue;
            }

            var title = link["title"] is JsonValue titleValue && titleValue.TryGetValue<string>(out var text) && text.Trim().Length > 0 ? text.Trim() : href;
            var type = link["type"] is JsonValue typeValue && typeValue.TryGetValue<string>(out var media) ? media : null;
            entries.Add(new EpubContentsEntry(title, href, depth, LocatorFor(href, type)));
            if (link["children"] is JsonArray children)
            {
                Walk(children, depth + 1, entries);
            }
        }
    }
}

/// <summary>
/// The way back after a jump (<c>ebook-reader</c>, "Following an internal link", "Returning from any jump"). A move the
/// app asked for as a jump (contents, a bookmark, a search hit, a highlight) remembers where the reader was; a move it
/// did not ask for that lands in another resource is a link the reader followed, and remembers the same. A page turn and
/// the voice following its sentence are moves the app asked for that are not jumps. Using the way back is not itself a
/// place to return from, and a newer jump replaces it.
/// </summary>
public sealed class EpubJumps
{
    private bool _movingItself;

    /// <summary>The locator the renderer last reported.</summary>
    public string? Current { get; private set; }

    /// <summary>Where the way back goes, or <c>null</c> when none is offered.</summary>
    public string? Return { get; private set; }

    /// <summary>Before a jump the app asks for: the place being left becomes the way back.</summary>
    public void Jumping()
    {
        if (Current is not null)
        {
            Return = Current;
        }

        _movingItself = true;
    }

    /// <summary>Before a move the app asks for that is not a jump: a page turn, the voice following its sentence.</summary>
    public void Turning() => _movingItself = true;

    /// <summary>Takes the way back, once: the locator to go to, or <c>null</c> when none is offered.</summary>
    public string? Back()
    {
        var target = Return;
        Return = null;
        _movingItself = target is not null || _movingItself;
        return target;
    }

    /// <summary>A <c>locator</c> message arrived.</summary>
    public void Moved(string locatorJson)
    {
        var previous = Current;
        Current = locatorJson;
        if (_movingItself)
        {
            _movingItself = false;
            return;
        }

        if (previous is not null && EpubPlace.Of(previous).Href != EpubPlace.Of(locatorJson).Href)
        {
            Return = previous;
        }
    }
}

/// <summary>
/// How far through a reflowable book the reader is, in one line (<c>ebook-reader</c>, "Progress display", "A publication
/// that declares no chapters"): the share of the book and what is left of the chapter, never a page number, since pages
/// move with typography; the share alone when the book declares no chapters.
/// </summary>
public static class EpubProgressLine
{
    /// <param name="withChapter">The format with the share read <c>{0}</c> and the share of the chapter left <c>{1}</c>.</param>
    /// <param name="alone">The format with the share read <c>{0}</c> alone.</param>
    public static string Text(string withChapter, string alone, double total, double chapter, bool declaresChapters)
    {
        var read = (int)Math.Round(Math.Clamp(total, 0, 1) * 100, MidpointRounding.AwayFromZero);
        var left = (int)Math.Round((1 - Math.Clamp(chapter, 0, 1)) * 100, MidpointRounding.AwayFromZero);
        return declaresChapters
            ? string.Format(CultureInfo.CurrentCulture, withChapter, read, left)
            : string.Format(CultureInfo.CurrentCulture, alone, read);
    }
}
