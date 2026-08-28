package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BorderCropTest {
    /** A page with [margin] pixels of [paper] around a block of [art]. */
    private fun page(
        width: Int = 100,
        height: Int = 100,
        margin: Int,
        paper: Int = 255,
        art: Int = 40,
    ): (Int, Int) -> Int = { x, y ->
        val inside = x >= margin && y >= margin && x < width - margin && y < height - margin
        if (inside) art else paper
    }

    @Test
    fun `a white margin is found on every edge`() {
        val inset = BorderCrop.inset(100, 100, page(margin = 10))
        assertEquals(BorderCrop.Inset(10, 10, 10, 10), inset)
    }

    @Test
    fun `a black margin is found too`() {
        // `comic-reader` says "white or black". A scan of a dark page on a dark platen has
        // the same problem and the same remedy.
        val inset = BorderCrop.inset(100, 100, page(margin = 6, paper = 0, art = 200))
        assertEquals(6, inset.top)
    }

    @Test
    fun `a page with no margin is left alone`() {
        assertTrue(BorderCrop.inset(100, 100) { _, _ -> 128 }.isEmpty)
    }

    @Test
    fun `a mid-grey band is not a margin`() {
        // Flat grey is as likely to be artwork as border, and cropping into a page is worse
        // than leaving its border on.
        assertTrue(BorderCrop.inset(100, 100, page(margin = 10, paper = 128)).isEmpty)
    }

    @Test
    fun `a gradient is not a margin`() {
        // The fixture pages are gradients, and every row of one is uniform along its own
        // length. Without an edge to end at, a gradient would read as a deep margin and the
        // top of the artwork would be quietly cut off.
        assertTrue(BorderCrop.inset(100, 100) { _, y -> 255 - y * 2 }.isEmpty)
    }

    @Test
    fun `a page that is all one colour is left alone`() {
        // No edge means no margin. A page with nothing on it has nothing to trim to.
        assertTrue(BorderCrop.inset(100, 100) { _, _ -> 255 }.isEmpty)
    }

    @Test
    fun `nothing is trimmed past the limit`() {
        val inset = BorderCrop.inset(100, 100, page(margin = 45))
        assertTrue("something is always left", inset.top + inset.bottom < 100)
        assertTrue(inset.top <= 40)
    }

    @Test
    fun `a page too small to sample is left alone`() {
        assertTrue(BorderCrop.inset(1, 1) { _, _ -> 255 }.isEmpty)
    }
}
