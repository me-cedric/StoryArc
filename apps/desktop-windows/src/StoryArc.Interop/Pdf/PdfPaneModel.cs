using System.Globalization;

namespace StoryArc.Interop.Pdf;

/// <summary>One row of the contents pane: an outline entry at its depth, or a search hit on a page.</summary>
/// <param name="PageIndex">The page to go to, from zero, or <c>null</c> for an outline entry that points nowhere.</param>
public sealed record PdfPaneRow(string Title, string Detail, int Depth, int? PageIndex);

/// <summary>
/// The contents pane of a PDF reader window (desktop-clients task 4.17; ebook-reader "PDF rendering"
/// and "Navigation and annotation"): the outline flattened with its depth, and a search whose rows
/// name the page and its hit count. Both are absent, not empty, when the file has no text layer,
/// so a scanned file reads as a comic with the text controls hidden (ebook-reader, "Scanned PDF").
/// The engine calls are injected, so the rules test without PDFium.
/// </summary>
public sealed class PdfPaneModel
{
    private readonly Func<string, IReadOnlyList<PdfSearchHit>> _search;
    private readonly IReadOnlyList<PdfOutlineEntry> _outline;

    public PdfPaneModel(bool hasTextLayer, IReadOnlyList<PdfOutlineEntry> outline, Func<string, IReadOnlyList<PdfSearchHit>> search)
    {
        HasTextLayer = hasTextLayer;
        _outline = outline;
        _search = search;
    }

    /// <summary>Whether the file carries text at all; without it, selection and search are not offered.</summary>
    public bool HasTextLayer { get; }

    /// <summary>Whether the file declares an outline; without one, the contents list is not offered either.</summary>
    public bool HasOutline => _outline.Count > 0;

    /// <summary>Whether the pane has anything to show: an outline, or a search over a text layer.</summary>
    public bool IsAvailable => HasTextLayer || HasOutline;

    /// <summary>The outline in reading order, each entry at its depth, with its page number from one as the detail.</summary>
    public IReadOnlyList<PdfPaneRow> OutlineRows(string pageFormat)
    {
        var rows = new List<PdfPaneRow>();
        Flatten(_outline, 0, rows, pageFormat);
        return rows;
    }

    /// <summary>
    /// The pages that hold <paramref name="query"/>, one row a page with how many hits it carries. A blank
    /// query is no search; a file with no text layer answers nothing without asking the engine.
    /// </summary>
    public IReadOnlyList<PdfPaneRow> SearchRows(string query, string pageFormat, string hitsFormat)
    {
        if (!HasTextLayer || string.IsNullOrWhiteSpace(query))
        {
            return [];
        }

        return _search(query.Trim())
            .Select(hit => new PdfPaneRow(
                string.Format(CultureInfo.CurrentCulture, pageFormat, hit.Page + 1),
                string.Format(CultureInfo.CurrentCulture, hitsFormat, hit.Rects.Count),
                0,
                hit.Page))
            .ToList();
    }

    /// <summary>Where the row in reading order that covers <paramref name="pageIndex"/> is, for marking the chapter being read.</summary>
    public int? OutlineRowFor(int pageIndex, string pageFormat)
    {
        int? found = null;
        var rows = OutlineRows(pageFormat);
        for (var row = 0; row < rows.Count; row++)
        {
            if (rows[row].PageIndex is { } page && page <= pageIndex)
            {
                found = row;
            }
        }

        return found;
    }

    private static void Flatten(IReadOnlyList<PdfOutlineEntry> entries, int depth, List<PdfPaneRow> rows, string pageFormat)
    {
        foreach (var entry in entries)
        {
            var detail = entry.Page is { } page ? string.Format(CultureInfo.CurrentCulture, pageFormat, page + 1) : string.Empty;
            rows.Add(new PdfPaneRow(entry.Title, detail, depth, entry.Page));
            Flatten(entry.Children, depth + 1, rows, pageFormat);
        }
    }
}
