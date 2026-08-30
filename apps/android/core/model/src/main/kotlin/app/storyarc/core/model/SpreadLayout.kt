package app.storyarc.core.model

/**
 * One slot in the reader's page order: a page on its own, or two facing pages.
 *
 * [leading] and [trailing] are in the publication's own order, not in screen order.
 * `comic-reader` asks for a pair "side by side in the correct order for the reading
 * direction", and which side each page lands on is the view's business — a manga spread
 * reads 4 then 5 exactly as a western one does, it just puts 4 on the right.
 */
data class Spread(val leading: Int, val trailing: Int? = null) {
    /** The pages in this slot, in reading order. */
    val pages: List<Int> get() = if (trailing == null) listOf(leading) else listOf(leading, trailing)

    val isPair: Boolean get() = trailing != null
}

/**
 * The reader's page order once two pages may share the screen.
 *
 * `comic-reader`: "WHEN two consecutive pages are portrait and the device is in landscape
 * THEN they are shown side by side in the correct order for the reading direction AND a
 * page detected as a single wide spread is shown alone, never split across two turns AND
 * the user can offset the pairing by one page, for publications whose cover throws the
 * pairing off."
 *
 * All three rules live here rather than in the screen, because they are arithmetic and
 * arithmetic is the thing that diverges silently between two codebases. The screen asks
 * for a layout and then only ever counts *slots*; the view model keeps counting pages the
 * way the publication does, so the indicator still says "12 of 220".
 *
 * [single] is the portrait case and the continuous-scroll case, and it is deliberately
 * the same type: every screen the reader draws goes through a layout, so there is no
 * second code path that only runs when a device is held one way up.
 *
 * iOS's `SpreadLayout` is the same type.
 */
class SpreadLayout private constructor(
    /** The slots, in the publication's own order. */
    val slots: List<Spread>,
) {
    /**
     * Which slot each page landed in, by page number.
     *
     * Precomputed rather than searched: the reader asks this on every recomposition, for
     * the slider, the strip and the counter, and a scan of two hundred slots per pass is
     * work that never had to happen.
     */
    private val slotOfPage: IntArray = IntArray(slots.sumOf { it.pages.size }).also { lookup ->
        slots.forEachIndexed { slot, spread ->
            spread.pages.forEach { page -> if (page in lookup.indices) lookup[page] = slot }
        }
    }

    val count: Int get() = slots.size

    /**
     * The slot a page is shown in. Zero for a page that is not in this layout, which is
     * the same answer the reader gives for any index it cannot place.
     */
    fun slotContaining(page: Int): Int = if (page in slotOfPage.indices) slotOfPage[page] else 0

    fun slotAt(slot: Int): Spread? = slots.getOrNull(slot)

    /**
     * Whether anything here is actually a pair.
     *
     * What decides whether the reader offers the offset control at all: a publication of
     * nothing but wide pages has a layout with no pairing to shift.
     */
    val hasPairs: Boolean get() = slots.any { it.isPair }

    override fun equals(other: Any?): Boolean = other is SpreadLayout && other.slots == slots

    override fun hashCode(): Int = slots.hashCode()

    companion object {
        /**
         * Every page on its own.
         *
         * Portrait, a continuous scroll, and a publication of one page all want this.
         */
        fun single(pageCount: Int): SpreadLayout =
            SpreadLayout((0 until maxOf(0, pageCount)).map { Spread(it) })

        /**
         * Facing pages, paired.
         *
         * @param wide pages that take the width of two — declared by `ComicInfo` or found
         *   to be landscape when they decoded. Each one stands alone, and so does the page
         *   that would otherwise have been paired with it: pairing a portrait page with
         *   the *next* portrait page across a spread would put two unrelated halves of the
         *   story beside each other.
         * @param isOffset whether to shift the pairing by one. A comic whose cover is page
         *   one pairs 1-2, 3-4 by default, which is off by one for the printed book — the
         *   reader says so and the cover then stands alone.
         */
        fun paired(pageCount: Int, wide: Set<Int>, isOffset: Boolean): SpreadLayout {
            val slots = mutableListOf<Spread>()
            var index = 0
            if (isOffset && pageCount > 0) {
                slots += Spread(0)
                index = 1
            }
            while (index < pageCount) {
                val alone = index in wide || index + 1 >= pageCount || index + 1 in wide
                if (alone) {
                    slots += Spread(index)
                    index += 1
                } else {
                    slots += Spread(index, index + 1)
                    index += 2
                }
            }
            return SpreadLayout(slots)
        }
    }
}
