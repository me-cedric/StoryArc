using System.Globalization;
using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Library;

/// <summary>The cover ladder: what a cell shows while its cover is on the way (desktop-clients task 2.47a).</summary>
public enum CoverStep
{
    /// <summary>A quiet placeholder in the page's ratio, never a spinner.</summary>
    Placeholder,
    Thumbnail,
    Full,
}

/// <summary>One cell of the grid or one row of the list, ready to draw. The decode of its cover never blocks a scroll.</summary>
public sealed record LibraryCell(
    string Id,
    string Title,
    string? Subtitle,
    string AccessibleName,
    double Progress,
    bool IsDownloaded,
    bool IsUnreadable,
    string? UnreadableReason);

/// <summary>A group of cells under one heading: a series, or the publications outside any series.</summary>
public sealed record LibrarySection(string? Series, IReadOnlyList<LibraryCell> Cells);

/// <summary>
/// The library grid and list over the records the core's queries return (desktop-clients task
/// 2.47a, after 2.23a): presentation, grouping by series, single selection and modifier-click
/// selection. Pure, so the cases of 2.23a test on any host; the <c>ItemsView</c> binds to it.
/// </summary>
public sealed class LibraryViewModel
{
    private readonly List<LibraryRecord> _records = [];
    private readonly HashSet<string> _selected = new(StringComparer.Ordinal);
    private string? _anchor;

    public LibraryPresentation Presentation { get; set; } = LibraryPresentation.Grid;

    public bool GroupBySeries { get; set; }

    public IReadOnlyList<LibraryRecord> Records => _records;

    public bool IsEmpty => _records.Count == 0;

    public int Count => _records.Count;

    public IReadOnlySet<string> Selected => _selected;

    public int SelectedCount => _selected.Count;

    /// <summary>Selection mode swaps the toolbar row for the selection actions while anything is selected.</summary>
    public bool IsSelectionMode => _selected.Count > 0;

    /// <summary>Replaces the records in one pass, as a scan or a query answer does. The selection keeps what still exists.</summary>
    public void Load(IEnumerable<LibraryRecord> records)
    {
        _records.Clear();
        _records.AddRange(records);
        _selected.IntersectWith(_records.Select(record => record.Id));
        if (_anchor is not null && !_selected.Contains(_anchor))
        {
            _anchor = null;
        }
    }

    /// <summary>The cells in their order, grouped by series when asked; one section with no series otherwise.</summary>
    public IReadOnlyList<LibrarySection> Sections()
    {
        if (!GroupBySeries)
        {
            return [new LibrarySection(null, _records.Select(Cell).ToList())];
        }

        return _records
            .GroupBy(record => record.Series, StringComparer.Ordinal)
            .OrderBy(group => group.Key is null ? 1 : 0)
            .ThenBy(group => group.Key, StringComparer.CurrentCultureIgnoreCase)
            .Select(group => new LibrarySection(group.Key, group.Select(Cell).ToList()))
            .ToList();
    }

    /// <summary>A plain click: this one and nothing else.</summary>
    public void Select(string id)
    {
        _selected.Clear();
        _selected.Add(id);
        _anchor = id;
    }

    /// <summary>A Control-click: adds or removes this one and leaves the rest.</summary>
    public void ToggleSelect(string id)
    {
        if (!_selected.Remove(id))
        {
            _selected.Add(id);
        }

        _anchor = id;
    }

    /// <summary>A Shift-click: every record from the anchor to this one, in display order.</summary>
    public void SelectRange(string id)
    {
        if (_anchor is null)
        {
            Select(id);
            return;
        }

        var ids = _records.Select(record => record.Id).ToList();
        var from = ids.IndexOf(_anchor);
        var to = ids.IndexOf(id);
        if (from < 0 || to < 0)
        {
            Select(id);
            return;
        }

        _selected.Clear();
        for (var index = Math.Min(from, to); index <= Math.Max(from, to); index++)
        {
            _selected.Add(ids[index]);
        }
    }

    public void ClearSelection()
    {
        _selected.Clear();
        _anchor = null;
    }

    public bool IsSelected(string id) => _selected.Contains(id);

    /// <summary>
    /// The cell of a record. The accessible name is what Narrator reads for the cover (docs/designs/
    /// desktop/windows.md, section 10): title, series, issue, percent read, downloaded.
    /// </summary>
    public static LibraryCell Cell(LibraryRecord record)
    {
        var subtitle = record.Series ?? record.Author;
        var parts = new List<string> { record.Title };
        if (record.Series is not null)
        {
            parts.Add(record.Series);
        }

        if (record.IssueNumber is { } issue)
        {
            parts.Add(string.Create(CultureInfo.CurrentCulture, $"issue {issue:0.##}"));
        }

        if (record.IsUnreadable)
        {
            parts.Add(record.UnreadableReason!);
        }
        else if (record.Progress > 0)
        {
            parts.Add(string.Create(CultureInfo.CurrentCulture, $"{Math.Round(record.Progress * 100)} percent read"));
        }

        if (record.IsDownloaded)
        {
            parts.Add("downloaded");
        }

        return new LibraryCell(
            record.Id,
            record.Title,
            subtitle,
            string.Join(", ", parts),
            record.Progress,
            record.IsDownloaded,
            record.IsUnreadable,
            record.UnreadableReason);
    }

    /// <summary>The next rung of the cover ladder once a decode lands: placeholder, thumbnail, full cover.</summary>
    public static CoverStep NextCoverStep(CoverStep current) => current switch
    {
        CoverStep.Placeholder => CoverStep.Thumbnail,
        _ => CoverStep.Full,
    };
}
