using System.Globalization;

namespace StoryArc.Interop.Playback;

/// <summary>
/// The coverless well of the player (audio-playback, "A publication with no cover"): the publication's kind as a symbol over the
/// format's name, the treatment every other surface draws, and never the title, which every surface states beside it.
/// </summary>
public sealed record PlayerArtwork(PlaybackKind Kind, string FormatName)
{
    /// <summary>The well for an item: a narrated book is an audiobook, a voice reads a book; the format is the file's own suffix.</summary>
    public static PlayerArtwork Of(PlaybackItem item) =>
        new(item.Kind, Path.GetExtension(item.PublicationId).TrimStart('.').ToUpperInvariant());
}

/// <summary>
/// An audiobook on its publication's page, before it plays (audio-playback, "Chapters before the first minute"): the chapters in
/// order with their durations and marks, the book's length when it has no chapters to list, and what the primary action says.
/// Looking at the list changes nothing; starting from a chapter is the listener's choice.
/// </summary>
public sealed record AudiobookDetail(IReadOnlyList<ChapterRow> Rows, TimeSpan Duration, string? ResumeChapter, bool HasStarted)
{
    /// <summary>A list of one row tells a listener nothing, so a book with one part states its length instead.</summary>
    public bool ListsChapters => Rows.Count > 1;

    /// <param name="chapters">The file's chapter markers, in order.</param>
    /// <param name="duration">The book's length.</param>
    /// <param name="saved">Where the book was left, or <c>null</c> when it was never started.</param>
    public static AudiobookDetail Of(IReadOnlyList<PlaybackChapter> chapters, TimeSpan duration, TimeSpan? saved)
    {
        var started = saved is { } at && at > TimeSpan.Zero;
        var position = saved ?? TimeSpan.Zero;
        var current = started ? Skips.ChapterAt(chapters, position) : null;
        var rows = chapters.Select((chapter, index) =>
        {
            var mark = index == current ? ChapterMark.InProgress : started && chapter.End <= position ? ChapterMark.Finished : ChapterMark.NotReached;
            TimeSpan? remaining = mark == ChapterMark.InProgress ? chapter.End - position : null;
            return new ChapterRow(index, chapter.Title, chapter.Duration, mark, remaining);
        }).ToList();
        return new AudiobookDetail(rows, duration, current is { } index && chapters.Count > 1 ? chapters[index].Title : null, started);
    }

    /// <summary>
    /// The primary action: <paramref name="listen"/> for a book never started; <paramref name="continueIn"/> (<c>{0}</c>, the chapter)
    /// for one left inside a chapter; <paramref name="continueListening"/> for one started that has no chapters to name.
    /// </summary>
    public string PrimaryLabel(string listen, string continueIn, string continueListening) =>
        !HasStarted ? listen
            : ResumeChapter is { } chapter ? string.Format(CultureInfo.CurrentCulture, continueIn, chapter)
            : continueListening;
}
