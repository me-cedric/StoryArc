using System.Globalization;

namespace StoryArc.Interop.Library;

/// <summary>
/// From the seam's records to what the library shows (desktop-clients tasks 2.47a and 2.47c): the
/// <see cref="LibraryRecord"/> of a core record and its progress, and the two Home shelves. The
/// shelves mirror storyarc-core's <c>LibraryIndex::continue_reading</c> and <c>up_next</c> (task
/// 2.8a), which mirror StoryArcKit's <c>HomeShelves</c>; the seam does not export the query yet,
/// so the rules are repeated here and the tests hold them to the same cases.
/// </summary>
public static class CoreLibrary
{
    /// <summary>How many publications a Home shelf shows at most.</summary>
    public const int ShelfLimit = 12;

    /// <summary>
    /// The library record of a core record found in the folder source <paramref name="sourceId"/>.
    /// A file in a folder on this machine is on the device, so it counts as downloaded. Returns
    /// <c>null</c> for a record with no path, which a folder source never writes.
    /// </summary>
    public static LibraryRecord? Record(CorePublication core, CoreProgress? progress, string sourceId)
    {
        if (core.Identity.NormalizedPath is not { Length: > 0 } path)
        {
            return null;
        }

        return new LibraryRecord(
            Id: path,
            Title: core.DisplayTitle,
            Series: core.Series,
            IssueNumber: IssueNumber(core.Number),
            Author: core.Authors is { Count: > 0 } authors ? authors[0] : null,
            Format: FormatOf(core.Format),
            SourceId: sourceId,
            Progress: progress?.Fraction ?? 0,
            IsDownloaded: true,
            AddedAt: core.AddedAt ?? core.ModifiedAt ?? DateTimeOffset.UnixEpoch,
            LastReadAt: progress is null ? null : ParseMoment(progress.UpdatedAt),
            Year: core.Year is { } year ? (int)year : null,
            FileSize: core.FileSize ?? 0,
            UnreadableReason: null,
            Core: core);
    }

    /// <summary>The issue number as the core sorts it: the digits and points of the text, or <c>null</c> when there are none.</summary>
    public static double? IssueNumber(string? number)
    {
        if (string.IsNullOrEmpty(number))
        {
            return null;
        }

        var digits = new string(number.Where(c => char.IsAsciiDigit(c) || c == '.').ToArray());
        return double.TryParse(digits, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : null;
    }

    /// <summary>The core's format name as the library's enumeration. Every audio container is an audiobook.</summary>
    public static PublicationFormat FormatOf(string format) => format switch
    {
        "cbr" => PublicationFormat.Cbr,
        "cbt" => PublicationFormat.Cbt,
        "imageFolder" => PublicationFormat.ImageFolder,
        "epub" => PublicationFormat.Epub,
        "pdf" => PublicationFormat.Pdf,
        "m4b" or "mp3" or "flac" or "ogg" or "audioFolder" => PublicationFormat.Audiobook,
        _ => PublicationFormat.Cbz,
    };

    /// <summary>
    /// Continue reading: the publications in progress, most recently read first, ties by title.
    /// Empty, never a heading over a gap, when nothing is in progress.
    /// </summary>
    public static IReadOnlyList<LibraryRecord> ContinueReading(IEnumerable<LibraryRecord> records, int limit = ShelfLimit) =>
        records
            .Where(record => record.ReadingState == ReadingState.InProgress)
            .OrderByDescending(record => record.LastReadAt ?? DateTimeOffset.MinValue)
            .ThenBy(record => record.Title, StringComparer.Ordinal)
            .Take(limit)
            .ToList();

    /// <summary>
    /// Up next: the next unread issue of each series the reader has started, most recently read
    /// series first. A series with something part-read offers nothing (Continue reading has it), and
    /// so do a series with nothing finished and one read to the end. A gap is not offered again.
    /// </summary>
    public static IReadOnlyList<LibraryRecord> UpNext(IEnumerable<LibraryRecord> records, int limit = ShelfLimit)
    {
        var library = records.ToList();
        var offered = new List<(LibraryRecord Candidate, DateTimeOffset When)>();
        foreach (var issues in library.Where(record => record.Series is not null).GroupBy(record => record.Series!, StringComparer.Ordinal))
        {
            var series = issues.ToList();
            if (series.Any(issue => issue.ReadingState == ReadingState.InProgress))
            {
                continue;
            }

            var finished = series.Where(issue => issue.ReadingState == ReadingState.Finished).ToList();
            var furthest = finished.FirstOrDefault(issue => Next(issue, finished) is null);
            if (furthest is null || Next(furthest, series) is not { } candidate || candidate.ReadingState != ReadingState.Unread)
            {
                continue;
            }

            offered.Add((candidate, furthest.LastReadAt ?? DateTimeOffset.MinValue));
        }

        return offered
            .OrderByDescending(pair => pair.When)
            .ThenBy(pair => pair.Candidate.Title, StringComparer.Ordinal)
            .Take(limit)
            .Select(pair => pair.Candidate)
            .ToList();
    }

    /// <summary>The next openable publication in the same series by issue number, or <c>null</c>.</summary>
    public static LibraryRecord? Next(LibraryRecord publication, IEnumerable<LibraryRecord> library)
    {
        if (publication.Series is null)
        {
            return null;
        }

        var current = publication.IssueNumber ?? double.MaxValue;
        return library
            .Where(candidate => candidate.Id != publication.Id
                && candidate.Series == publication.Series
                && !candidate.IsUnreadable
                && (candidate.IssueNumber ?? double.MaxValue) > current)
            .MinBy(candidate => candidate.IssueNumber ?? double.MaxValue);
    }

    private static DateTimeOffset? ParseMoment(string text) =>
        DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var moment) ? moment : null;
}
