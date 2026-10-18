using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StoryArc.Interop.Epub;

/// <summary>
/// One message the renderer posted (<c>apps/desktop-web/epub/README.md</c>, "The host API"): its type,
/// its sequence number and the rest as JSON. The host keeps the latest sequence per type and drops
/// an older message that arrives after a newer one.
/// </summary>
public sealed record RendererMessage(string Type, long Seq, JsonObject Body)
{
    /// <summary>Parses the JSON the web view handed over, or <c>null</c> when it is not a message.</summary>
    public static RendererMessage? TryParse(string json)
    {
        JsonNode? node;
        try
        {
            node = JsonNode.Parse(json);
        }
        catch (JsonException)
        {
            return null;
        }

        if (node is not JsonObject body || body["type"] is not JsonValue typeValue || !typeValue.TryGetValue<string>(out var type))
        {
            return null;
        }

        var seq = body["seq"] is JsonValue seqValue && seqValue.TryGetValue<long>(out var number) ? number : 0;
        return new RendererMessage(type, seq, body);
    }

    /// <summary>For a <c>locator</c> message: the position (from one) and the total progression, or <c>null</c> when it carries neither.</summary>
    public (int Position, double TotalProgression)? Position()
    {
        if (Body["locator"] is not JsonObject locator || locator["locations"] is not JsonObject locations)
        {
            return null;
        }

        var position = locations["position"] is JsonValue p && p.TryGetValue<int>(out var number) ? number : 0;
        var total = locations["totalProgression"] is JsonValue t && t.TryGetValue<double>(out var share) ? share : 0;
        return position <= 0 ? null : (position, total);
    }

    /// <summary>For a <c>locator</c> message: the locator as JSON, which a bookmark, the way back and the progress line keep.</summary>
    public string? LocatorJson() => Type == "locator" && Body["locator"] is JsonObject locator ? locator.ToJsonString() : null;

    /// <summary>For a <c>selection</c> message: the text chosen and its locator, or <c>null</c> when the selection was cleared.</summary>
    public EpubSelection? Selection()
    {
        var text = Type == "selection" && Body["text"] is JsonValue value && value.TryGetValue<string>(out var chosen) ? chosen.Trim() : string.Empty;
        return text.Length > 0 && Body["locator"] is JsonObject locator ? new EpubSelection(text, locator.ToJsonString()) : null;
    }

    /// <summary>For a <c>footnote</c> message: the note's href and its text.</summary>
    public EpubFootnote? Footnote() =>
        Type == "footnote" && Body["href"] is JsonValue href && href.TryGetValue<string>(out var target)
            ? new EpubFootnote(target, Body["text"] is JsonValue text && text.TryGetValue<string>(out var note) ? note : string.Empty)
            : null;

    /// <summary>For a <c>highlight-activated</c> message: the id of the decoration the reader clicked.</summary>
    public string? ActivatedId() =>
        Type == "highlight-activated" && Body["id"] is JsonValue id && id.TryGetValue<string>(out var text) ? text : null;

    /// <summary>For a <c>search-results</c> message: the id of the search it answers.</summary>
    public string? SearchId() => Type != "search-results" ? null : Body["id"] switch
    {
        JsonValue value when value.TryGetValue<string>(out var text) => text,
        JsonValue value when value.TryGetValue<long>(out var number) => number.ToString(CultureInfo.InvariantCulture),
        _ => null,
    };

    /// <summary>For a <c>search-results</c> message: whether the search has looked through every chapter.</summary>
    public bool SearchDone() => Type == "search-results" && Body["done"] is JsonValue done && done.TryGetValue<bool>(out var flag) && flag;

    /// <summary>For a <c>search-results</c> message: its hits, each with its chapter, the match in its context and the locator.</summary>
    public IReadOnlyList<EpubSearchHit> SearchHits()
    {
        if (Type != "search-results" || Body["results"] is not JsonArray results)
        {
            return [];
        }

        var hits = new List<EpubSearchHit>();
        foreach (var result in results)
        {
            if (result?["locator"] is not JsonObject locator)
            {
                continue;
            }

            var text = locator["text"] as JsonObject;
            hits.Add(new EpubSearchHit(
                Text(locator["title"]),
                Text(text?["before"]) ?? string.Empty,
                Text(text?["highlight"]) ?? string.Empty,
                Text(text?["after"]) ?? string.Empty,
                locator.ToJsonString()));
        }

        return hits;
    }

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    /// <summary>For a <c>link</c> message: the http or https address the reader followed out of the publication.</summary>
    public Uri? OutboundLink() =>
        Type == "link" && Body["href"] is JsonValue value && value.TryGetValue<string>(out var href)
            && Uri.TryCreate(href, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https"
            ? uri
            : null;
}

/// <summary>
/// The messages the host sends the renderer, as JSON, each with the next sequence number. The window
/// posts them with <c>CoreWebView2.PostWebMessageAsJson</c>.
/// </summary>
public sealed class HostCommands
{
    private long _seq;

    public string Next() => Plain("next");

    public string Previous() => Plain("previous");

    /// <summary>Go to <paramref name="locatorJson"/>, a locator object the renderer or the positions list produced.</summary>
    public string Go(string locatorJson) => Wrap("go", new JsonObject { ["locator"] = JsonNode.Parse(locatorJson) });

    public string Search(string id, string query) => Wrap("search", new JsonObject { ["id"] = id, ["query"] = query });

    /// <summary>A theme preset: its name and the axes it sets, the rest cleared (<see cref="ReadingThemes.Axes"/>).</summary>
    public string Theme(string name, JsonObject axes) =>
        Wrap("theme", new JsonObject { ["theme"] = new JsonObject { ["name"] = name, ["axes"] = axes } });

    /// <summary>Every highlight on the page, replacing what the page had (<see cref="EpubMarks.HighlightItems"/>).</summary>
    public string Highlights(JsonArray items) => Wrap("highlights", new JsonObject { ["items"] = items });

    private string Plain(string type) => Wrap(type, new JsonObject());

    private string Wrap(string type, JsonObject body)
    {
        body["type"] = type;
        body["seq"] = Interlocked.Increment(ref _seq);
        return body.ToJsonString();
    }
}

/// <summary>
/// The reading position of an EPUB as the progress store keeps it: the position number from one of
/// the positions list, which the phones show, mapped onto the store's page index from zero so one
/// record shape serves every format (desktop-clients task 4.16 with 2.44).
/// </summary>
public static class EpubProgress
{
    /// <summary>The page index the store takes for a position number.</summary>
    public static int PageIndex(int position, int positionCount) => Math.Clamp(position - 1, 0, Math.Max(0, positionCount - 1));

    /// <summary>The locator of a stored page index, from the positions list, or <c>null</c> for an empty list.</summary>
    public static string? LocatorAt(string positionsJson, int pageIndex)
    {
        if (JsonNode.Parse(positionsJson) is not JsonArray positions || positions.Count == 0)
        {
            return null;
        }

        return positions[Math.Clamp(pageIndex, 0, positions.Count - 1)]?.ToJsonString();
    }

    /// <summary>How many positions the list holds.</summary>
    public static int Count(string positionsJson) => JsonNode.Parse(positionsJson) is JsonArray positions ? positions.Count : 0;

    /// <summary>The label under the page: position and count, in the reader's language through <paramref name="format"/> (<c>{0}</c>, <c>{1}</c>).</summary>
    public static string Label(string format, int position, int positionCount) =>
        string.Format(CultureInfo.CurrentCulture, format, position, positionCount);
}
