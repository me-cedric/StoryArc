package app.storyarc.feature.reader

/**
 * Whether the first few decoded pages of a publication read as a webtoon.
 *
 * `comic-reader` recognises a webtoon by pages "materially taller than they are wide",
 * measured from early pages rather than declared, because a webtoon rarely says it is
 * one and waiting for the tallest page of the whole run means waiting for the whole
 * publication.
 *
 * **More than one page**, because the first alone is not enough: a webtoon chapter
 * often opens on a short title image, and a rule that stopped at page one read that as
 * ordinary panels and defaulted Scroll to horizontal. A class of its own, held outside
 * [ReaderViewModel], so `EarlyPageTallnessTest` can drive it with plain numbers — the
 * view model needs a real decoded `Bitmap`, which needs a device this module's unit
 * tests do not have. iOS's `EarlyPageTallness` is the same rule.
 */
internal class EarlyPageTallness {
    var tallestRatio: Double = 0.0
        private set

    /** Notes one decoded page's height-over-width ratio, if it is early enough to count. */
    fun note(ratio: Double, index: Int) {
        if (index >= SAMPLE_COUNT) return
        tallestRatio = maxOf(tallestRatio, ratio)
    }

    companion object {
        /**
         * How many of the earliest pages count. Three catches a one-page title card
         * without waiting long enough to matter for anything longer.
         */
        const val SAMPLE_COUNT = 3
    }
}
