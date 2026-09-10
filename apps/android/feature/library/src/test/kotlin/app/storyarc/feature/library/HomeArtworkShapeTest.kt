package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a cover is drawn in its own shape, inside a bound.
 *
 * `home-screen`, *Artwork is not letterboxed*: a cover is "drawn whole at its own
 * proportions with no bar of background above, below or beside it", and "never cropped to
 * fill the area". The reader met the failure as "a black border above/below" the artwork --
 * a 2:3 box with a differently shaped cover letterboxed inside it.
 *
 * The bound is what keeps the row of cards one height: without it a tall cover would make
 * its own card taller than the rest. `HomeCardRowTest` is the other half, on a device's
 * layout rather than this arithmetic.
 */
class HomeArtworkShapeTest {

    private val slot = 200.dp

    @Test
    fun `a wide cover keeps the slot's width and takes only the height it needs`() {
        val size = homeArtSize(slot, coverWidth = 1000, coverHeight = 500)

        assertEquals(200.dp, size.width)
        assertEquals(100.dp, size.height)
    }

    @Test
    fun `a 2 to 3 cover fills the slot exactly, which is the bound`() {
        val size = homeArtSize(slot, coverWidth = 800, coverHeight = 1200)

        assertEquals(200.dp, size.width)
        assertEquals(300.dp, size.height)
    }

    @Test
    fun `a cover taller than the bound is scaled down, not cropped`() {
        val size = homeArtSize(slot, coverWidth = 500, coverHeight = 1500)

        assertEquals(
            "A cover past the bound has to give up height, and the bound is 2:3 of the slot.",
            300.dp,
            size.height,
        )
        assertTrue(
            "It gave up height without giving up width, so the picture is cropped: $size.",
            size.width < slot,
        )
        assertEquals(100.dp, size.width)
    }

    @Test
    fun `every shape keeps its aspect and stays inside the bound`() {
        val shapes = listOf(
            1000 to 400,
            1200 to 800,
            800 to 1200,
            600 to 1400,
            300 to 2000,
            1 to 1,
        )

        for ((w, h) in shapes) {
            val size = homeArtSize(slot, w, h)
            val wanted = w.toFloat() / h.toFloat()
            val drawn = size.width.value / size.height.value

            assertEquals("A ${w}x$h cover was drawn at $size.", wanted, drawn, 0.001f)
            assertTrue("A ${w}x$h cover was drawn wider than its slot: $size.", size.width <= slot)
            assertTrue(
                "A ${w}x$h cover was drawn past the bound: $size.",
                size.height <= slot * HOME_COVER_ASPECT,
            )
        }
    }

    @Test
    fun `a cover of no known shape gets the box the coverless well draws`() {
        val size = homeArtSize(slot, coverWidth = 0, coverHeight = 0)

        assertEquals(200.dp, size.width)
        assertEquals(300.dp, size.height)
    }
}
