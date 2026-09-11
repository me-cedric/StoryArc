package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaSeries

/**
 * What to call one chapter of a Kavita series, and what its issue number is.
 *
 * One place, because the answer is drawn in three: as a row's title, as `#<number>` in the
 * caption beneath it, and as the name a download is filed under. Each had its own version of
 * this and they disagreed, which is what a reader met -- a row headed with the series' name
 * and a line under it reading the same name and "#-100000".
 *
 * **Kavita writes `-100000` for a chapter with no number at all**: a collected edition, a
 * volume with one part. It is a sentinel and not a number, and neither is any other
 * negative. `KavitaChapter.issueNumber` is where that rule lives, so a screen drawing a
 * chapter and a shelf drawing a row cannot disagree about it -- which they did, and a
 * reader met "-100000" in a chapter list while the shelf beside it was already guarded.
 */
internal object KavitaNaming {

    /**
     * The chapter's issue number, or null where Kavita is saying it has none.
     *
     * `KavitaChapter.issueNumber` is where the rule lives now -- every screen that draws a
     * chapter needs the same answer, and one that asked separately is how "-100000"
     * reached a chapter list while the shelf was already guarded against it.
     */
    fun issueNumber(chapter: KavitaChapter): String? = chapter.issueNumber

    /**
     * The title a reader sees.
     *
     * Three cases. A chapter with a title of its own keeps it. A numbered one reads
     * `<series> #<number>`, which is the house format -- the same shape a filename-derived
     * title already has, so a server's issue and a scanned one read alike. And an unnumbered
     * one is left as the series' own name, which is what the reader would have called it; a
     * cell headed "43" names nothing, and one headed "-100000" names less.
     */
    fun title(series: KavitaSeries, chapter: KavitaChapter): String {
        chapter.properTitle?.let { return it }
        return issueNumber(chapter)?.let { "${series.name} #$it" } ?: series.name
    }
}
