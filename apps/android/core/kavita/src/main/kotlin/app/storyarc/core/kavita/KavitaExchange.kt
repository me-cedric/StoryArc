package app.storyarc.core.kavita

import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import kotlin.math.roundToInt

/**
 * One position a Kavita server has not been told about, and the record that position becomes
 * once it has.
 */
data class KavitaOwed(
    /** The chapter Kavita keys its progress row on. */
    val chapterId: Int,
    /** Kavita's `pageNum` -- the page the reader is on, counted from zero. */
    val pageNum: Int,
    /**
     * What to write locally once the server has taken the position, carrying the stamp that
     * says it is no longer only this device's opinion.
     *
     * Held back rather than written with the rest: a position the server never received is
     * not synchronised, and calling it so would make the next merge treat an untouched local
     * record as agreed with a server that has never heard of it.
     */
    val settled: ReadingProgress,
)

/**
 * Sorting a merge into the two halves only a server can settle: what it must be told, and
 * what a local record may then call synchronised.
 *
 * The merge table itself is [app.storyarc.core.model.ProgressMerge]'s and the sorting into
 * piles is [ProgressPull]'s. What is added here is the part that is specific to Kavita and
 * still pure -- a chapter's `pagesRead` is a position, a position is a `pageNum`, and an
 * exchange that actually happened is a stamp on the record. Pure so that both platforms can
 * assert the same cases without a server, which is the whole reason the table lives outside a
 * view model. iOS's `KavitaExchange` is the same three answers.
 */
data class KavitaExchange(
    /** Records to write now. Every one the server already holds carries the stamp. */
    val toSave: List<ReadingProgress> = emptyList(),
    /** Positions the server is behind on, in the order the merge produced them. */
    val owed: List<KavitaOwed> = emptyList(),
) {
    companion object {

        /**
         * The position a chapter's `pagesRead` describes.
         *
         * Kavita counts pages *read*; a position names the page the reader is *on*, so the
         * two differ by one. Clamped at both ends rather than trusted: the count arrives over
         * the network from a server that may be mid-scan, and a page index past the end of a
         * chapter is a resume point that opens nothing.
         */
        fun position(pagesRead: Int, pages: Int): ReadingPosition =
            if (pages <= 0) {
                ReadingPosition.Page(0, 0)
            } else {
                ReadingPosition.Page((pagesRead - 1).coerceIn(0, pages - 1), pages)
            }

        /**
         * The `pageNum` a server is told, from a stored position and the chapter's length.
         *
         * A reflowable position is carried across by its fraction, because that is the only
         * part of it that means anything to a server counting pages -- ADR-0006. A one-page
         * chapter has one answer and no arithmetic to do.
         */
        fun pageNumber(position: ReadingPosition, pages: Int): Int {
            if (pages <= 1) return 0
            return when (position) {
                is ReadingPosition.Page -> position.index.coerceIn(0, pages - 1)
                is ReadingPosition.Reflowable ->
                    (position.progression.coerceIn(0.0, 1.0) * (pages - 1))
                        .roundToInt()
                        .coerceIn(0, pages - 1)
            }
        }

        /**
         * The record a source has just taken this position from, or agreed it with.
         *
         * The stamp is the whole point: [app.storyarc.core.model.ProgressMerge] tells
         * "changed since the last sync" from "untouched" by comparing against it, and nothing
         * wrote it, so every record looked changed and the quiet adopt could never happen.
         */
        fun settled(record: ReadingProgress): ReadingProgress =
            record.copy(syncedPosition = record.position)

        /**
         * Sorts one merge against the chapters it came from.
         *
         * A record with no chapter behind it is left out of what is owed rather than guessed
         * at: the position is real, but without a chapter there is no row on the server to
         * put it in.
         */
        fun of(pull: ProgressPull, against: Map<String, KavitaChapter>): KavitaExchange {
            val owed = pull.toPush.mapNotNull { record ->
                val chapter = against[record.identity.stableId] ?: return@mapNotNull null
                if (chapter.pages <= 0) return@mapNotNull null
                KavitaOwed(
                    chapterId = chapter.id,
                    pageNum = pageNumber(record.position, chapter.pages),
                    settled = settled(record),
                )
            }

            // A record that is still owed is written as it stands and stamped later, when the
            // server has actually taken it. Everything else in `toSave` came from the server,
            // so the server holds it by definition.
            val owing = owed.map { it.settled.identity.stableId }.toSet()
            val toSave = pull.toSave.map { record ->
                if (record.identity.stableId in owing) record else settled(record)
            }

            return KavitaExchange(toSave = toSave, owed = owed)
        }
    }
}
