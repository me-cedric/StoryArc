package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A cover's lower bound follows the room the window has.
 *
 * `design.md` §4 gives three numbers and the old grid used one, which is why a 1400 dp
 * tablet showed roughly eleven columns of phone-sized covers.
 */
class CoverMinimumWidthTest {

    @Test
    fun `a phone gets the smallest readable cover`() {
        assertEquals(104.dp, coverMinimumWidth(360))
        assertEquals(104.dp, coverMinimumWidth(599))
    }

    @Test
    fun `a portrait tablet and a half-screen window get the middle size`() {
        assertEquals(132.dp, coverMinimumWidth(600))
        assertEquals(132.dp, coverMinimumWidth(839))
    }

    @Test
    fun `a landscape tablet gets covers worth its width`() {
        assertEquals(158.dp, coverMinimumWidth(840))
        assertEquals(158.dp, coverMinimumWidth(1400))
    }

    /**
     * A window is measured as zero before it is laid out, and the narrow answer is the one
     * that is safe to be briefly wrong with — every column fits at 104 dp.
     */
    @Test
    fun `an unmeasured window gets the phone size rather than a crash`() {
        assertEquals(104.dp, coverMinimumWidth(0))
    }

    /** The pair has to stay a range: a minimum above the maximum would invert the grid. */
    @Test
    fun `every minimum stays under the maximum`() {
        for (width in listOf(0, 320, 600, 840, 1400, 4000)) {
            assertTrue(coverMinimumWidth(width) < COVER_MAXIMUM_WIDTH)
        }
    }
}
