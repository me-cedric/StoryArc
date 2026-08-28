package app.storyarc.core.model

import kotlin.math.abs

/**
 * Finds the uniform margin around a scanned page.
 *
 * `comic-reader`: "uniform white or black margins are detected and trimmed per page". A scan
 * taken on a flatbed carries the lid; a scan taken from print carries the paper. Both are a
 * band of one colour around the artwork, and both cost a reader a third of the screen.
 *
 * The rule is deliberately timid. A line is margin only if every sample along it is within
 * [TOLERANCE] of where the run started, that colour is near-white or near-black, and the run
 * ends at an [EDGE]. Artwork that happens to start pale is not a margin, and a page cropped
 * into is worse than a page not cropped at all. iOS's `BorderCrop` is the same rule.
 */
object BorderCrop {
    /**
     * How far two samples may differ and still count as the same colour, out of 255.
     *
     * Twelve, because a JPEG's flat white is not flat: the block edges of a scanned margin
     * measured eight or nine apart on the fixture scans, and a threshold below that found no
     * margin at all.
     */
    const val TOLERANCE = 12

    /**
     * How far the first line of artwork must sit from the margin for the margin to be one.
     *
     * A margin ends at an edge. Without this a smooth gradient reads as a deep margin --
     * every one of its rows is uniform along its own length -- and the top of the artwork is
     * quietly cut off.
     */
    const val EDGE = TOLERANCE * 3

    /**
     * How much of a page may be taken. Beyond this the detection is wrong about something.
     *
     * A page that is nine tenths margin is a page whose artwork the sampler missed, and
     * handing the reader a sliver is the one outcome worse than handing them the margin.
     */
    const val LIMIT = 0.4

    /** One page's edges, as the number of pixels to trim from each. */
    data class Inset(
        val top: Int = 0,
        val left: Int = 0,
        val bottom: Int = 0,
        val right: Int = 0,
    ) {
        val isEmpty: Boolean get() = this == NONE

        companion object {
            val NONE = Inset()
        }
    }

    /** What to trim from a page of this size. [sample] reads a brightness, 0..255. */
    fun inset(width: Int, height: Int, sample: (Int, Int) -> Int): Inset {
        if (width <= 2 || height <= 2) return Inset.NONE
        val capX = (width * LIMIT).toInt()
        val capY = (height * LIMIT).toInt()
        // Probed down the middle, not down the corner: a corner stays margin all the way
        // through the page, so a run measured there never meets the edge that ends it.
        val midX = width / 2
        val midY = height / 2

        return Inset(
            top = run(capY, { sample(midX, it) }) { uniformRow(it, width, sample) },
            left = run(capX, { sample(it, midY) }) { uniformColumn(it, height, sample) },
            bottom = run(capY, { sample(midX, height - 1 - it) }) {
                uniformRow(height - 1 - it, width, sample)
            },
            right = run(capX, { sample(width - 1 - it, midY) }) {
                uniformColumn(width - 1 - it, height, sample)
            },
        )
    }

    /** How many lines in from an edge are margin, and zero unless they end at one. */
    private fun run(cap: Int, value: (Int) -> Int, isMargin: (Int) -> Boolean): Int {
        val reference = value(0)
        var count = 0
        // Each line must look like the first one, not merely like the line before it: a
        // gradient satisfies the second and none of it is a margin.
        while (count < cap && isMargin(count) && abs(value(count) - reference) <= TOLERANCE) {
            count += 1
        }
        return if (count > 0 && abs(value(count) - reference) >= EDGE) count else 0
    }

    private fun uniformRow(row: Int, width: Int, sample: (Int, Int) -> Int): Boolean {
        val first = sample(0, row)
        if (!isPaperOrInk(first)) return false
        // Sampled rather than read whole: a margin is uniform by definition, and reading
        // every pixel of every edge of every page is the difference between a page turn that
        // feels immediate and one that does not.
        val step = maxOf(1, width / 64)
        return (0 until width step step).all { abs(sample(it, row) - first) <= TOLERANCE }
    }

    private fun uniformColumn(column: Int, height: Int, sample: (Int, Int) -> Int): Boolean {
        val first = sample(column, 0)
        if (!isPaperOrInk(first)) return false
        val step = maxOf(1, height / 64)
        return (0 until height step step).all { abs(sample(column, it) - first) <= TOLERANCE }
    }

    /**
     * Whether a value is close enough to white or to black to be a margin at all.
     *
     * `comic-reader` says "white or black margins", and it means it: a flat mid-grey band is
     * as likely to be artwork as it is to be a border.
     */
    private fun isPaperOrInk(value: Int): Boolean = value >= 226 || value <= 30
}
