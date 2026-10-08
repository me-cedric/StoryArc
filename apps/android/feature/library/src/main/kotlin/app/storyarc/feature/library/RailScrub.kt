package app.storyarc.feature.library

import kotlin.math.floor

/**
 * Which letter a finger on the A to Z rail is on.
 *
 * `close-the-audited-gaps` 24.6, decision O23: the rail is **one control**, as Android's own
 * fast scroller is. A tap or a drag selects the letter under the finger, and [IndexRail]
 * chooses a letter once when the finger arrives on it rather than on every point of the drag.
 *
 * Pure so `RailScrubTest` can state the arithmetic once. iOS's `RailScrub` is the twin.
 */
internal object RailScrub {

    /**
     * The letter at a height along the rail, counted over **every** entry.
     *
     * @param y the finger's height, from the top of the rail's hit region.
     * @param height the hit region's height, padding included.
     * @param inset the padding above the first letter and below the last, which a finger can land
     *   on and which counts as the first and the last letter.
     * @param count how many entries the shelf offers, drawn or not.
     * @return `null` when there is nothing to choose.
     */
    fun index(y: Float, height: Float, inset: Float, count: Int): Int? {
        if (count <= 0) return null
        val span = height - 2 * inset
        if (span <= 0f) return 0
        val fraction = (y - inset) / span
        return floor(fraction * count).toInt().coerceIn(0, count - 1)
    }
}
