using System.Globalization;
using StoryArc.Interop.Text;

namespace StoryArc.Interop.Library;

/// <summary>The destinations of the navigation pane, as the iOS tab bar names them.</summary>
public enum LibraryDestination
{
    Home,
    Library,
    Downloads,
    Search,
}

/// <summary>The sort keys of the library (the <c>library_sort_*</c> strings).</summary>
public enum SortKey
{
    Title,
    Series,
    DateAdded,
    LastRead,
    Progress,
    Year,
    FileSize,
}

/// <summary>The filters of the library: format, source, reading state and download state. <c>null</c> means any.</summary>
public sealed record LibraryFilters(PublicationFormat? Format, string? SourceId, ReadingState? ReadingState, bool? IsDownloaded)
{
    public static LibraryFilters None { get; } = new(null, null, null, null);

    public int ActiveCount =>
        (Format is null ? 0 : 1) + (SourceId is null ? 0 : 1) + (ReadingState is null ? 0 : 1) + (IsDownloaded is null ? 0 : 1);

    public bool Admits(LibraryRecord record) =>
        (Format is null || record.Format == Format)
        && (SourceId is null || record.SourceId == SourceId)
        && (ReadingState is null || record.ReadingState == ReadingState)
        && (IsDownloaded is null || record.IsDownloaded == IsDownloaded);
}

/// <summary>
/// The query state behind the title-bar search field, the filter flyout and the sort flyout
/// (desktop-clients task 2.47b, after 2.23b; desktop-experience "Search on a desktop"). The field
/// stays in the title bar: while text is in it the results take over the content column, and
/// clearing it or pressing Escape returns the column to the destination the reader came from.
/// The core's query (task 2.8a) will answer the search under its collation; until it is bound,
/// <see cref="Apply"/> runs the same rules here so the view binds to one shape.
/// </summary>
public sealed class LibraryQueryState
{
    private LibraryDestination _origin = LibraryDestination.Home;

    public string SearchText { get; private set; } = string.Empty;

    public LibraryFilters Filters { get; set; } = LibraryFilters.None;

    public SortKey Sort { get; set; } = SortKey.Title;

    public bool SortDescending { get; set; }

    /// <summary>Whether text is in the field, so the results view replaces the content column.</summary>
    public bool IsShowingResults => !string.IsNullOrWhiteSpace(SearchText);

    /// <summary>What the content column shows: the results while text is in the field, else the destination the reader chose.</summary>
    public LibraryDestination ContentDestination => IsShowingResults ? LibraryDestination.Search : _origin;

    /// <summary>The reader chose a destination in the pane. Choosing one while searching ends the search.</summary>
    public void Navigate(LibraryDestination destination)
    {
        _origin = destination == LibraryDestination.Search ? _origin : destination;
        if (destination != LibraryDestination.Search)
        {
            SearchText = string.Empty;
        }
    }

    /// <summary>Text typed in the field. The field itself never moves; only the content column answers.</summary>
    public void SetSearchText(string text) => SearchText = text;

    /// <summary>Escape in the field, or the clear button: the content column returns to where the reader came from.</summary>
    public void ClearSearch() => SearchText = string.Empty;

    /// <summary>The records that match the text and the filters, in the sort order.</summary>
    public IReadOnlyList<LibraryRecord> Apply(IEnumerable<LibraryRecord> records)
    {
        var folded = TextFold.Fold(SearchText);
        var matching = records.Where(record => Filters.Admits(record) && MatchesText(record, folded));
        return Sorted(matching).ToList();
    }

    private static bool MatchesText(LibraryRecord record, string foldedQuery)
    {
        if (foldedQuery.Length == 0)
        {
            return true;
        }

        return TextFold.Fold(record.Title).Contains(foldedQuery, StringComparison.Ordinal)
            || (record.Series is not null && TextFold.Fold(record.Series).Contains(foldedQuery, StringComparison.Ordinal))
            || (record.Author is not null && TextFold.Fold(record.Author).Contains(foldedQuery, StringComparison.Ordinal));
    }

    private IEnumerable<LibraryRecord> Sorted(IEnumerable<LibraryRecord> records)
    {
        var text = StringComparer.Create(CultureInfo.CurrentCulture, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace);
        IOrderedEnumerable<LibraryRecord> ordered = Sort switch
        {
            SortKey.Series => Order(records, record => record.Series ?? record.Title, text).ThenBy(record => record.IssueNumber ?? 0),
            SortKey.DateAdded => Order(records, record => record.AddedAt),
            SortKey.LastRead => Order(records, record => record.LastReadAt ?? DateTimeOffset.MinValue),
            SortKey.Progress => Order(records, record => record.Progress),
            SortKey.Year => Order(records, record => record.Year ?? 0),
            SortKey.FileSize => Order(records, record => record.FileSize),
            _ => Order(records, record => record.Title, text),
        };
        return ordered.ThenBy(record => record.Title, text);
    }

    private IOrderedEnumerable<LibraryRecord> Order<TKey>(IEnumerable<LibraryRecord> records, Func<LibraryRecord, TKey> key, IComparer<TKey>? comparer = null) =>
        SortDescending ? records.OrderByDescending(key, comparer) : records.OrderBy(key, comparer);
}
