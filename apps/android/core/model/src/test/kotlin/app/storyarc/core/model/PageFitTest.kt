package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The four fit modes, as a scale against fit-to-screen.
 *
 * `comic-reader` names the four; the arithmetic is what decides whether choosing
 * one shows the page or throws it off the edge. iOS's `PageFitTests` asserts the
 * same table.
 */
class PageFitTest {
    /** A tall page on a phone: the fit leaves bars either side. */
    private val fittedWidth = 300f
    private val fittedHeight = 600f
    private val viewportWidth = 400f
    private val viewportHeight = 600f

    private fun scale(fit: PageFit, pixelWidth: Float = 1200f) =
        fit.scale(fittedWidth, fittedHeight, viewportWidth, viewportHeight, pixelWidth)

    @Test
    fun `fit-to-screen is the scale everything else is measured against`() {
        assertEquals(1f, scale(PageFit.SCREEN), 0.001f)
    }

    @Test
    fun `fit-to-width fills the width the fit left over`() {
        val scale = scale(PageFit.WIDTH)
        assertEquals(400f / 300f, scale, 0.001f)
        // And the page is then taller than the screen, which is the point: it
        // scrolls down instead of shrinking to fit.
        assertTrue(fittedHeight * scale > viewportHeight)
    }

    @Test
    fun `fit-to-height is already the fit for a page the screen bounds vertically`() {
        assertEquals(1f, scale(PageFit.HEIGHT), 0.001f)
    }

    @Test
    fun `original size is the image's own pixels against the space it was fitted into`() {
        assertEquals(4f, scale(PageFit.ORIGINAL), 0.001f)
    }

    @Test
    fun `a page smaller than the screen is never shrunk below the fit`() {
        // 100 pixels of scan in 300 points of space. Shown at its own pixels it
        // would be a postage stamp in the middle of a black screen.
        assertEquals(1f, scale(PageFit.ORIGINAL, pixelWidth = 100f), 0.001f)
    }

    @Test
    fun `a page with no size yet does not divide by zero`() {
        assertEquals(1f, PageFit.WIDTH.scale(0f, 0f, viewportWidth, viewportHeight, 1200f), 0.001f)
    }
}
