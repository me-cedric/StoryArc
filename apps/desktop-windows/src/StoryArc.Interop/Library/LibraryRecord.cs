namespace StoryArc.Interop.Library;

public enum PublicationFormat
{
    Cbz,
    Cbr,
    Cbt,
    ImageFolder,
    Epub,
    Pdf,
    Audiobook,
}

public enum ReadingState
{
    Unread,
    InProgress,
    Finished,
}

/// <summary>
/// One publication as the library shows it (tasks 2.47a and 2.47b). The view models test over
/// hand-made records; the app makes them from the seam's records with <see cref="CoreLibrary.Record"/>,
/// which keeps the core's record in <paramref name="Core"/> for the detail page and the reader.
/// </summary>
/// <param name="Id">The publication's file path for a folder source: the key a reader window and the session use.</param>
/// <param name="Progress">0 to 1. Finished at 1.</param>
/// <param name="UnreadableReason">Why the file could not be opened, or <c>null</c> when it opens.</param>
/// <param name="Core">The core's record, or <c>null</c> for a record made by hand.</param>
public sealed record LibraryRecord(
    string Id,
    string Title,
    string? Series,
    double? IssueNumber,
    string? Author,
    PublicationFormat Format,
    string SourceId,
    double Progress,
    bool IsDownloaded,
    DateTimeOffset AddedAt,
    DateTimeOffset? LastReadAt,
    int? Year,
    long FileSize,
    string? UnreadableReason,
    CorePublication? Core = null)
{
    public bool IsUnreadable => UnreadableReason is not null;

    public ReadingState ReadingState =>
        Progress >= 1 ? ReadingState.Finished : Progress > 0 ? ReadingState.InProgress : ReadingState.Unread;
}
