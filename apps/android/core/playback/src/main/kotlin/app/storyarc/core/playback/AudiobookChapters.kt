package app.storyarc.core.playback

/**
 * A chapter mark, as any container reports one.
 *
 * Deliberately not media3's `Chapter`. The rules below — what an unchaptered book gets,
 * what an untitled mark is called, what happens to a mark that starts after the file ends
 * — are decisions, and a decision expressed in a decoder's own types can only be asserted
 * with that decoder running. This shape is the seam: the adapter that turns a media3
 * `Chapter` into one of these is three lines, and everything worth arguing about is on
 * this side of it.
 */
data class ChapterMark(
    /** What the container calls it, or null when it calls it nothing. */
    val title: String?,
    val startMillis: Long,
    val endMillis: Long,
    /** Some containers mark a chapter as not for showing. */
    val isHidden: Boolean = false,
)

/**
 * The parts a publication plays in, from whatever its container said.
 *
 * `publication-formats`: "an unchaptered audiobook is a normal audiobook", so the answer is
 * never an empty list — the whole of a single file stands in for a chapter, and the caller
 * gets one part rather than nothing to draw.
 */
object AudiobookChapters {

    /**
     * @param marks the container's own chapter marks, in any order.
     * @param totalMillis the file's length when the decoder knows it.
     * @param fallbackTitle what to call the whole of the file when it carries no marks —
     *   the publication's title, which is the only thing a listener would recognise.
     * @param chapterWord the reader's own word for a chapter, for the marks a container
     *   left untitled. Passed in rather than read from a resource, because this module
     *   ships none — the same rule `:core:designsystem` follows, and for the same reason:
     *   a layer that owned a word would own vocabulary, and vocabulary belongs to the app.
     */
    fun parts(
        marks: List<ChapterMark>,
        totalMillis: Long?,
        fallbackTitle: String,
        chapterWord: String = "Chapter",
    ): List<PlaybackPart> {
        val usable = marks
            .filterNot { it.isHidden }
            // A mark that ends where it starts, or before it, describes no audio. Dropped
            // rather than kept as a zero-length row nothing can play or seek to.
            .filter { it.endMillis > it.startMillis }
            .sortedBy { it.startMillis }

        if (usable.isEmpty()) return listOf(
            PlaybackPart(
                title = fallbackTitle,
                duration = totalMillis?.let(PlaybackDuration::Known) ?: PlaybackDuration.Unknown,
            ),
        )

        return usable.mapIndexed { index, mark ->
            PlaybackPart(
                title = mark.title?.trim()?.ifEmpty { null } ?: "$chapterWord ${index + 1}",
                duration = PlaybackDuration.Known(mark.endMillis - mark.startMillis),
            )
        }
    }

    /**
     * Where each part starts, for a publication whose parts are marks inside one file.
     *
     * A folder's parts are separate items and the player seeks between them itself; a
     * chaptered M4B is one item, so moving to a chapter is a seek and something has to
     * know where to. The list is index-aligned with [parts] over the same marks.
     */
    fun offsets(marks: List<ChapterMark>): List<Long> = marks
        .filterNot { it.isHidden }
        .filter { it.endMillis > it.startMillis }
        .sortedBy { it.startMillis }
        .map { it.startMillis }

    /**
     * Which part a position falls in.
     *
     * Binary-search-free because a chapter list is tens of entries, not thousands, and a
     * scan that is obviously right beats a search that is nearly right.
     */
    fun partAt(offsets: List<Long>, positionMillis: Long): Int {
        if (offsets.isEmpty()) return 0
        var index = 0
        for (candidate in offsets.indices) {
            if (offsets[candidate] <= positionMillis) index = candidate else break
        }
        return index
    }
}
