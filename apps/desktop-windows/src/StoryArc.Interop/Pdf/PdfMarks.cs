using System.Globalization;
using System.Text.Json.Nodes;
using StoryArc.Interop.Epub;

namespace StoryArc.Interop.Pdf;

/// <summary>
/// A selection in a text PDF as the same record an EPUB highlight is (ebook-reader, "Text-based PDF": "stored as the same
/// record and exported by the same document"): an <see cref="EpubHighlight"/> whose locator names the page, the offset of the
/// passage in the page's text, and the passage. The page's text is the engine's (<see cref="PdfDocument.PageText"/>); the
/// window draws the highlights in that text, since the page itself is an image.
/// </summary>
public static class PdfMarks
{
    /// <summary>The locator of a passage: <c>page-&lt;index&gt;</c> as its resource, the page from one as its position.</summary>
    public static string Locator(int pageIndex, int offset, string text) => new JsonObject
    {
        ["href"] = Href(pageIndex),
        ["type"] = "application/pdf",
        ["locations"] = new JsonObject { ["position"] = pageIndex + 1, ["offset"] = offset },
        ["text"] = new JsonObject { ["highlight"] = text },
    }.ToJsonString();

    /// <summary>The resource a page's marks are filed under.</summary>
    public static string Href(int pageIndex) => "page-" + pageIndex.ToString(CultureInfo.InvariantCulture);

    /// <summary>The page of a resource, for reading order; <c>int.MaxValue</c> for anything else.</summary>
    public static int PageOf(string href) =>
        href.StartsWith("page-", StringComparison.Ordinal) && int.TryParse(href.AsSpan(5), NumberStyles.None, CultureInfo.InvariantCulture, out var page) ? page : int.MaxValue;

    /// <summary>
    /// Where a highlight sits in its page's text: its offset when the text there is still the passage, else the first place
    /// the passage occurs, else <c>null</c>.
    /// </summary>
    public static (int Start, int Length)? RangeIn(string pageText, EpubHighlight highlight)
    {
        if (highlight.Text.Length == 0)
        {
            return null;
        }

        var offset = EpubPlace.Parse(highlight.Locator) is JsonObject locator && locator["locations"]?["offset"] is JsonValue value && value.TryGetValue<int>(out var stored) ? stored : -1;
        if (offset >= 0 && offset + highlight.Text.Length <= pageText.Length && string.CompareOrdinal(pageText, offset, highlight.Text, 0, highlight.Text.Length) == 0)
        {
            return (offset, highlight.Text.Length);
        }

        var found = pageText.IndexOf(highlight.Text, StringComparison.Ordinal);
        return found < 0 ? null : (found, highlight.Text.Length);
    }

    /// <summary>
    /// The offset of a selection in its page's text: the occurrence of <paramref name="selected"/> nearest the offset the text
    /// control reported, which counts its own structure and so is only close; -1 when the text holds no such passage.
    /// </summary>
    public static int OffsetNear(string pageText, string selected, int reported)
    {
        if (selected.Length == 0)
        {
            return -1;
        }

        var best = -1;
        for (var at = pageText.IndexOf(selected, StringComparison.Ordinal); at >= 0; at = pageText.IndexOf(selected, at + 1, StringComparison.Ordinal))
        {
            if (best < 0 || Math.Abs(at - reported) < Math.Abs(best - reported))
            {
                best = at;
            }
        }

        return best;
    }
}
