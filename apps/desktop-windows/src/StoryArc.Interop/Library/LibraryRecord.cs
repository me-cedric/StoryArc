namespace StoryArc.Interop.Library;

public enum PublicationFormat
{
    Cbz,
    Cbr,
    Cbt,
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
/// One publication as the library shows it. A local record for the view-model tests of tasks
/// 2.47a and 2.47b; the seam's record (lane C, task 2.1) replaces it when its JSON shape lands,
/// and the view models keep their tests.
/// </summary>
/// <param name="Progress">0 to 1. Finished at 1.</param>
/// <param name="UnreadableReason">Why the file could not be opened, or <c>null</c> when it opens.</param>
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
    string? UnreadableReason)
{
    public bool IsUnreadable => UnreadableReason is not null;

    public ReadingState ReadingState =>
        Progress >= 1 ? ReadingState.Finished : Progress > 0 ? ReadingState.InProgress : ReadingState.Unread;
}
