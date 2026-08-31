package app.storyarc.core.model

import kotlin.math.roundToInt

/**
 * Where a reader is in a reflowable publication, said in one line.
 *
 * `ebook-reader`, *Progress display*:
 *
 * > **THEN** one line states how far through the publication they are and how much of the
 * > current chapter is left, in words
 * > **AND** because reflowable page counts depend on typography, the app never presents a
 * > reflowable page number as a stable identity
 * > **AND** no slider is offered, and the position is not drawn over the page
 *
 * **This type has no page number in it, and that is the point.** *A publication that declares
 * no chapters* requires the line to state progress alone and to not "fall back to a page
 * count, because that is the identity the app refuses to present". A rule enforced by a branch
 * can be undone by an `else`; a rule enforced by the absence of a field cannot be undone
 * without changing the type both readers share.
 *
 * A rule rather than a rendering detail, which is why it lives here and not in either reader:
 * both need it, and a reader that says one thing on one platform and another on the other is
 * exactly the divergence this module exists to prevent. [TotalProgression] — the input to
 * this — lives here for the same reason. iOS mirrors it in `StoryArcCore`, and
 * `ReadingPositionLineTest` mirrors `ReadingPositionLineTests` case for case.
 */
data class ReadingPositionLine(
    /** How far through the whole publication, as a percentage a reader can read aloud. */
    val percentThrough: Int,
    /** The chapter the reader is in, or null where the publication declares no navigation. */
    val chapter: String?,
    /**
     * Roughly how much of that chapter is left, or null where there is no chapter to measure
     * or the renderer could not say where in it the reader is.
     */
    val chapterRemainder: ChapterRemainder?,
) {
    companion object {
        /**
         * Builds the line from what the renderer knows.
         *
         * @param totalProgression how far through the whole publication, 0…1. See
         *   [TotalProgression] for why the renderer's own answer is not trusted blindly.
         * @param chapter the current chapter's title. Blank and null are the same thing: a
         *   publication with no navigation, and Readium reports both.
         * @param withinChapter how far through the current resource, 0…1, or null when the
         *   renderer has not said.
         */
        fun of(
            totalProgression: Double,
            chapter: String?,
            withinChapter: Double?,
        ): ReadingPositionLine {
            val percent = (totalProgression.coerceIn(0.0, 1.0) * 100).roundToInt()
            val named = chapter?.trim()

            // No chapter, and therefore nothing to say about a chapter. Not a page count:
            // `ebook-reader` names that fallback and forbids it.
            if (named.isNullOrEmpty()) {
                return ReadingPositionLine(percent, chapter = null, chapterRemainder = null)
            }

            return ReadingPositionLine(
                percentThrough = percent,
                chapter = named,
                chapterRemainder = withinChapter?.let(ChapterRemainder::of),
            )
        }
    }
}

/**
 * How much of the current chapter is left, coarsely, in words.
 *
 * **Why words and not a second percentage.** The requirement says "how much of the current
 * chapter is left, in words", and a line reading *42% through · Chapter Three, 63% left* is
 * two numbers a reader has to hold at once to learn one thing. The coarse band is what a
 * reader actually wants from a chapter — whether to keep going before putting the book down —
 * and it is all a within-chapter percentage is accurate enough to say anyway: the renderer's
 * within-resource progression moves in jumps the width of a screen.
 *
 * Five bands rather than three: *nearly done* and *just begun* are the two a reader acts on,
 * and collapsing them into *less than half* and *more than half* loses exactly the decision
 * the line is there to inform.
 *
 * No string resource here: the enum lives in `:core:model`, and the domain has no business
 * holding UI copy. Each reader names the five bands from its own `strings.xml`.
 */
enum class ChapterRemainder {
    NEARLY_DONE,
    LESS_THAN_HALF_LEFT,
    ABOUT_HALF_LEFT,
    MORE_THAN_HALF_LEFT,
    JUST_BEGUN,
    ;

    companion object {
        /**
         * The band a within-chapter progression falls in.
         *
         * Measured on what is *left*, not on what is read: the line says how much is left, and
         * a threshold table written against the other quantity is one inversion away from
         * saying the opposite.
         *
         * The bands, by how much is left: under a tenth is nearly done, under two fifths is
         * less than half, up to three fifths is about half, under nine tenths is more than
         * half, and the rest is just begun. Each boundary belongs to the band below it.
         */
        fun of(withinChapter: Double): ChapterRemainder {
            val left = 1 - withinChapter.coerceIn(0.0, 1.0)
            return when {
                left < 0.1 -> NEARLY_DONE
                left < 0.4 -> LESS_THAN_HALF_LEFT
                left <= 0.6 -> ABOUT_HALF_LEFT
                left < 0.9 -> MORE_THAN_HALF_LEFT
                else -> JUST_BEGUN
            }
        }
    }
}
