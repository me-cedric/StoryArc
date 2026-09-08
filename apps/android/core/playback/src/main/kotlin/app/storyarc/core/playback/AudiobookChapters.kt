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
    /**
     * Where the mark ends, or null when the container says only where it starts.
     *
     * **Null is the ordinary case for an M4B, and reading it as unusable was the defect.** An
     * MP4 carries its chapters as a text track that a `chap` reference points at, and that
     * track states a title and a start and no end; media3 answers `C.TIME_UNSET`. ID3 `CHAP`
     * frames carry both ends, which is why a chaptered MP3 always listed its chapters and a
     * chaptered M4B listed one part. [AudiobookChapters.parts] fills an unstated end from the
     * next mark, which is what a chapter list already means.
     */
    val endMillis: Long?,
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
        val usable = usable(marks)

        if (usable.isEmpty()) return listOf(
            PlaybackPart(
                title = fallbackTitle,
                duration = totalMillis?.let(PlaybackDuration::Known) ?: PlaybackDuration.Unknown,
            ),
        )

        return usable.mapIndexed { index, mark ->
            // Where the container stated no end, the next mark's start is the end, and the
            // book's own length is the last mark's. Derived and not guessed: a chapter runs
            // until the one after it begins. Where nothing says how long the book is, the
            // last chapter states no length rather than an estimate.
            val ends = mark.endMillis
                ?: usable.getOrNull(index + 1)?.startMillis
                ?: totalMillis
            PlaybackPart(
                title = mark.title?.trim()?.ifEmpty { null } ?: "$chapterWord ${index + 1}",
                duration = ends
                    ?.takeIf { it > mark.startMillis }
                    ?.let { PlaybackDuration.Known(it - mark.startMillis) }
                    ?: PlaybackDuration.Unknown,
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
    fun offsets(marks: List<ChapterMark>): List<Long> = usable(marks).map { it.startMillis }

    /**
     * The marks that name a part, in playing order.
     *
     * One list for [parts] and [offsets], so the two cannot drop different marks and leave a
     * chapter row seeking to its neighbour. A hidden mark is not a part. A mark that ends at
     * or before it starts describes no audio, and some encoders write one at the end of a
     * file, so it is dropped rather than kept as a row nothing can play. A mark with no
     * stated end is kept: a start and a title are all a chapter row needs.
     */
    private fun usable(marks: List<ChapterMark>): List<ChapterMark> = marks
        .filterNot { it.isHidden }
        .filterNot { mark -> mark.endMillis != null && mark.endMillis <= mark.startMillis }
        .sortedBy { it.startMillis }

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
