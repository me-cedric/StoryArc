package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.RectF
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.Spread
import app.storyarc.core.model.pairsPages
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * That a spread curls as one sheet rather than losing a page.
 *
 * `comic-reader`: a pair is shown side by side "AND a page detected as a single wide spread is
 * shown alone, never split across two turns". Curl was excluded from the pairing, so a reader
 * who chose it in landscape stopped seeing spreads at all -- and the shader, handed the
 * leading page alone, turned half of one. D14 composites the slot into one texture instead.
 *
 * iOS's `SpreadTextureTests` asserts the same table.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SpreadTextureTest {

    private fun page(width: Int, height: Int): Bitmap =
        Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

    @Test
    fun `curl is one of the modes that pair`() {
        // The one-line defect. Every mode that draws a slot as a picture pairs; only the
        // strip does not.
        assertTrue(PageTransition.PAGE_CURL.pairsPages)
        assertTrue(PageTransition.SLIDE.pairsPages)
        assertTrue(PageTransition.FAST_FADE.pairsPages)
        assertFalse(PageTransition.VERTICAL_SCROLL.pairsPages)
        assertFalse(PageTransition.HORIZONTAL_SCROLL.pairsPages)
    }

    @Test
    fun `two pages make one texture twice as wide as either half`() {
        val texture = SpreadTexture.composite(listOf(page(400, 600), page(400, 600)))
        // The shader fits by ratio, so the shape is the whole of what it is handed: a spread
        // that came out one page wide would letterbox half the screen and turn one page.
        assertEquals(800, texture?.width)
        assertEquals(600, texture?.height)
    }

    @Test
    fun `a slot of one page is handed straight through`() {
        val only = page(400, 600)
        assertSame(only, SpreadTexture.composite(listOf(only)))
        assertNull(SpreadTexture.composite(emptyList()))
    }

    @Test
    fun `the halves are equal, and the taller page sets the height`() {
        // `HingeSpread` gives each page an equal share and `spreadTap` depends on that. A
        // composite that sized each half to its own page would move the tap zones off the
        // pages they belong to.
        val area = SpreadTexture.area(listOf(400 to 600, 300 to 900))
        assertEquals(900, area.height)
        // The first page at 900 high is 600 wide; the second is 300. The wider one sets it.
        assertEquals(600, area.half)
        assertEquals(1200, area.width)
    }

    @Test
    fun `a page narrower than its half is centred in it, not pushed against the fold`() {
        val placed = SpreadTexture.placed(300 to 900, x = 600, half = 600, height = 900)
        assertEquals(RectF(750f, 0f, 1050f, 900f), placed)
    }

    @Test
    fun `a page of no size places nothing rather than dividing by zero`() {
        assertEquals(RectF(), SpreadTexture.placed(0 to 0, x = 0, half = 10, height = 10))
        assertEquals(RectF(), SpreadTexture.placed(10 to 10, x = 0, half = 0, height = 0))
    }

    @Test
    fun `a pair is read out in screen order, which right-to-left reverses`() {
        val spread = Spread(leading = 4, trailing = 5)
        assertEquals(listOf(4, 5), spread.onScreen(isRightToLeft = false))
        assertEquals(listOf(5, 4), spread.onScreen(isRightToLeft = true))
        assertEquals(emptyList<Int>(), null.onScreen(isRightToLeft = false))
    }
}
