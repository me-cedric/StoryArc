package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The fraction through a page a continuous scroll sits at, and the pixel offset that
 * restores it. iOS's `ScrollProgressTests` asserts the same table, from a `CGRect`
 * rather than a pixel offset and size — the two platforms' own native shapes for
 * "where a page sits" — but the same fractions.
 */
class ScrollProgressTest {

    @Test
    fun `an offset of zero reads as the very start of the page`() {
        assertEquals(0f, ScrollProgress.fraction(offsetPx = 0, pageSizePx = 1000), 0f)
    }

    @Test
    fun `scrolled halfway through a page reads as one half`() {
        assertEquals(0.5f, ScrollProgress.fraction(offsetPx = 500, pageSizePx = 1000), 0f)
    }

    @Test
    fun `an offset past the page clamps to one, not past it`() {
        assertEquals(1f, ScrollProgress.fraction(offsetPx = 1500, pageSizePx = 1000), 0f)
    }

    @Test
    fun `a page with no size is never divided by zero`() {
        assertEquals(0f, ScrollProgress.fraction(offsetPx = 50, pageSizePx = 0), 0f)
    }

    @Test
    fun `the restored offset is the fraction scaled by the page's own size`() {
        assertEquals(300, ScrollProgress.offsetPixels(fraction = 0.3f, pageSizePx = 1000))
    }

    @Test
    fun `a stored fraction outside 0 to 1 is clamped before it becomes an offset`() {
        assertEquals(1000, ScrollProgress.offsetPixels(fraction = 4f, pageSizePx = 1000))
        assertEquals(0, ScrollProgress.offsetPixels(fraction = -1f, pageSizePx = 1000))
    }
}
