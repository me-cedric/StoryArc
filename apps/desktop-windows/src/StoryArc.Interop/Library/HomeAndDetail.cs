namespace StoryArc.Interop.Library;

/// <summary>The shelves Home can show, in their order (the <c>home_keepReading</c> and <c>home_upNext</c> strings).</summary>
public enum ShelfKind
{
    ContinueReading,
    UpNext,
}

/// <summary>One shelf of Home: its kind and its publications, never empty.</summary>
public sealed record HomeShelf(ShelfKind Kind, IReadOnlyList<LibraryRecord> Items);

/// <summary>
/// Home (desktop-clients task 2.47c, as 2.23c; capability <c>home-screen</c>): the window opens on
/// it, with Continue reading and Up next. A shelf with nothing on it is absent, not a heading over
/// a gap; with no shelf at all Home shows its one sentence (<c>home_nothingOpen</c>).
/// </summary>
public sealed record HomeShelves(IReadOnlyList<HomeShelf> Shelves)
{
    public bool IsEmpty => Shelves.Count == 0;

    public static HomeShelves From(IEnumerable<LibraryRecord> records)
    {
        var library = records.ToList();
        var shelves = new List<HomeShelf>();
        var reading = CoreLibrary.ContinueReading(library);
        if (reading.Count > 0)
        {
            shelves.Add(new HomeShelf(ShelfKind.ContinueReading, reading));
        }

        var next = CoreLibrary.UpNext(library);
        if (next.Count > 0)
        {
            shelves.Add(new HomeShelf(ShelfKind.UpNext, next));
        }

        return new HomeShelves(shelves);
    }
}

/// <summary>The one primary action of the detail page.</summary>
public enum DetailAction
{
    /// <summary>Unread: Read.</summary>
    Read,

    /// <summary>In progress: Continue at the saved page.</summary>
    Continue,

    /// <summary>Finished: Read again from the start.</summary>
    ReadAgain,

    /// <summary>Its source cannot be reached or the file cannot be opened: the action shows disabled, with the reason in grey.</summary>
    Unavailable,
}

/// <summary>What sits behind the title: the cover washed across the header, or a quiet placeholder when there is no cover.</summary>
public enum DetailCover
{
    Wash,
    Placeholder,
}

/// <summary>Where the file lives, for the one line the page names it with.</summary>
public enum DetailLocation
{
    /// <summary>On this device: <c>detail_provenance_device</c>.</summary>
    OnDevice,

    /// <summary>Its folder's volume or share is not answering: <c>detail_provenance_away___</c>, in grey.</summary>
    SourceOffline,
}

/// <summary>
/// The publication detail page (desktop-clients task 2.47d, as 2.23d; capability
/// <c>publication-detail</c>): pushed in the navigation frame, with the cover wash, one primary
/// action, a menu of the rest, and one line that names where the file lives.
/// </summary>
/// <param name="Subtitle">The series and number, when the publication has a series.</param>
/// <param name="Credits">The writers, then the pencillers.</param>
/// <param name="Folder">The folder that holds the file, as the location line names it.</param>
public sealed record PublicationDetail(
    string Id,
    string Title,
    string? Subtitle,
    IReadOnlyList<string> Credits,
    string? Summary,
    int? PageCount,
    double Progress,
    DetailCover Cover,
    DetailAction Action,
    DetailLocation Location,
    string Folder,
    string? UnavailableReason)
{
    /// <summary>The detail of <paramref name="record"/>, whose source is reachable when <paramref name="isSourceAvailable"/>.</summary>
    public static PublicationDetail Of(LibraryRecord record, bool isSourceAvailable)
    {
        var core = record.Core;
        var subtitle = record.Series is null
            ? null
            : core?.Number is { Length: > 0 } number ? $"{record.Series} #{number}" : record.Series;
        var credits = (core?.Authors ?? []).Concat(core?.Pencillers ?? []).Distinct(StringComparer.Ordinal).ToList();
        if (credits.Count == 0 && record.Author is not null)
        {
            credits.Add(record.Author);
        }

        var hasCover = core is { CoverPath: not null, PageCount: > 0 };
        var action = !isSourceAvailable || record.IsUnreadable
            ? DetailAction.Unavailable
            : record.ReadingState switch
            {
                ReadingState.Finished => DetailAction.ReadAgain,
                ReadingState.InProgress => DetailAction.Continue,
                _ => DetailAction.Read,
            };

        return new PublicationDetail(
            record.Id,
            record.Title,
            subtitle,
            credits,
            core?.Summary,
            core?.PageCount,
            record.Progress,
            hasCover ? DetailCover.Wash : DetailCover.Placeholder,
            action,
            isSourceAvailable ? DetailLocation.OnDevice : DetailLocation.SourceOffline,
            Path.GetDirectoryName(record.Id) ?? record.Id,
            record.UnreadableReason);
    }
}
