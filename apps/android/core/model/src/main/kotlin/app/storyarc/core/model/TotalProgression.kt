package app.storyarc.core.model

/**
 * How far through a whole publication a position is.
 *
 * A rule rather than a rendering detail, which is why it lives here and not in either
 * reader: both need it, and a renderer that reports one thing on one platform and
 * another on the other is exactly the divergence this module exists to prevent.
 */
object TotalProgression {

    /**
     * Resolves the renderer's own answer against where it says the reader is.
     *
     * Readium fills in a total progression only once it has computed a positions list,
     * which it does lazily and not at all for some publications. Without a fallback the
     * reader sits at "0% read" for a whole book, which is worse than an approximation —
     * so the fallback places the current resource in the reading order and adds how far
     * through that resource the reader is.
     *
     * The subtlety, and the reason this is a function rather than an elvis operator:
     * **a reported zero is not the same as no report.** In scroll mode Readium answers
     * `0.0` rather than nothing, so `reported ?: fallback` takes the zero and the reader
     * watches "0% read" while scrolling through chapter one. A reported zero that
     * contradicts where the renderer says the reader is, is not a report.
     *
     * @param reported what the renderer said, if it said anything.
     * @param within how far through the current resource, 0…1.
     * @param resourceIndex where that resource sits in the reading order, or negative if
     *   it could not be found.
     * @param resourceCount how many resources the reading order has.
     */
    fun resolve(
        reported: Double?,
        within: Double,
        resourceIndex: Int,
        resourceCount: Int,
    ): Double {
        val estimate = estimated(within, resourceIndex, resourceCount)
        if (reported == null) return estimate ?: 0.0
        // Trust the report unless it is a zero the position contradicts.
        if (reported == 0.0 && estimate != null && estimate > 0.0) return estimate
        return reported.coerceIn(0.0, 1.0)
    }

    /** Where the reader is, from the reading order alone. Null when it cannot be told. */
    private fun estimated(within: Double, resourceIndex: Int, resourceCount: Int): Double? {
        if (resourceCount <= 0 || resourceIndex < 0) return null
        return ((resourceIndex + within.coerceIn(0.0, 1.0)) / resourceCount).coerceIn(0.0, 1.0)
    }
}
