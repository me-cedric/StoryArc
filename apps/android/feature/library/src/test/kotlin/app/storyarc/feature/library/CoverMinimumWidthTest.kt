package app.storyarc.feature.library

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A cover's lower bound follows the room the window has, and the reader's font scale.
 *
 * `design.md` §4 gives three numbers and the old grid used one, which is why a 1400 dp
 * tablet showed roughly eleven columns of phone-sized covers.
 *
 * The font scale was the other missing input, and the shelf showed what that costs: at an
 * accessibility font scale a ~400 dp phone still laid out three columns, so a cover
 * captioned `Harbour Lights #1` wrapped and its neighbours' series lines truncated. The
 * artwork stayed recognisable and the caption stopped being readable, which is the wrong
 * way round. iOS's `CoverMinimumWidthTests` asserts the same bounds.
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

    // ── The reader's text size ───────────────────────────────────────────────────────

    /**
     * Android's own Font size slider stops at 1.3 outside accessibility settings, so 1.3 is
     * where the ordinary range ends. Every scale below it must leave `design.md`'s three
     * numbers exactly as they are.
     */
    @Test
    fun `an ordinary font scale leaves the documented tiers alone`() {
        for (scale in listOf(0.85f, 1f, 1.15f, 1.29f)) {
            assertEquals(104.dp, coverMinimumWidth(360, scale))
            assertEquals(132.dp, coverMinimumWidth(600, scale))
            assertEquals(158.dp, coverMinimumWidth(840, scale))
            assertEquals(COVER_MAXIMUM_WIDTH, coverMaximumWidth(scale))
        }
    }

    /**
     * One step, not a scale that follows the font: 1.3 and 2.0 get the same cover, because
     * what a cramped caption needs is one fewer column and a column is a step. iOS's
     * `coverMinimumWidth` lands on the same three numbers.
     */
    @Test
    fun `every tier steps once at an accessibility font scale`() {
        for (scale in listOf(1.3f, 1.5f, 1.8f, 2f)) {
            assertEquals(146.dp, coverMinimumWidth(360, scale))
            assertEquals(185.dp, coverMinimumWidth(600, scale))
            assertEquals(221.dp, coverMinimumWidth(840, scale))
        }
    }

    /**
     * The cap steps with the minimum, or it becomes the thing that decides the layout — see
     * [coverMaximumWidth]. 168 dp columns inside 221 dp slots leave a ragged strip of empty
     * shelf down the trailing edge of a tablet.
     */
    @Test
    fun `the maximum steps with the minimum`() {
        assertEquals(235.dp, coverMaximumWidth(1.5f))
        for (width in listOf(0, 320, 360, 600, 840, 1400, 4000)) {
            assertTrue(coverMinimumWidth(width, 1.5f) < coverMaximumWidth(1.5f))
        }
    }

    /**
     * The claim the whole change is for, put through the real grid: the phone in the
     * committed shelf screenshot is ~400 dp wide and lays out three 112 dp captions. At an
     * accessibility font scale it lays out two.
     *
     * Density 1, so a dp is a pixel. The window loses `gutter` on each side to the grid's
     * content padding and `md` between columns.
     */
    @Test
    fun `an accessibility font scale drops a phone from three columns to two`() {
        assertEquals(listOf(112, 112, 112), columns(windowWidthDp = 400, fontScale = 1f))
        assertEquals(listOf(174, 174), columns(windowWidthDp = 400, fontScale = 1.5f))
    }

    /**
     * And leaves alone the phone that had nothing to give. A 360 dp window is already at
     * two columns, and a step that took it to one would be trading a truncated caption for
     * a shelf you cannot browse.
     */
    @Test
    fun `a narrow phone keeps the two columns it already had`() {
        assertEquals(2, columns(windowWidthDp = 360, fontScale = 1f).size)
        assertEquals(2, columns(windowWidthDp = 360, fontScale = 1.5f).size)
    }

    /** What the grid really lays out at this window width and font scale. */
    private fun columns(windowWidthDp: Int, fontScale: Float): List<Int> {
        val cells = BoundedAdaptive(
            minSize = coverMinimumWidth(windowWidthDp, fontScale),
            maxSize = coverMaximumWidth(fontScale),
        )
        return with(cells) {
            with(Density(1f, fontScale)) {
                calculateCrossAxisCellSizes(
                    availableSize = windowWidthDp - GUTTER * 2,
                    spacing = COLUMN_SPACING,
                )
            }
        }
    }

    private companion object {
        /** `layout.json`: `gutter` 20 each side, `md` 12 between columns. */
        const val GUTTER = 20
        const val COLUMN_SPACING = 12
    }
}
