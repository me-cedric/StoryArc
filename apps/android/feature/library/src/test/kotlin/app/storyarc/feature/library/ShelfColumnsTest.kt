package app.storyarc.feature.library

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The 380 dp pane that drew one cover across its whole width.
 *
 * The numbers below are the shelf's real geometry: a 20 dp gutter on each side and 12 dp
 * between columns, which is what `CoverGrid` states.
 */
class ShelfColumnsTest {

    private val density = Density(1f)
    private val gutter = 20
    private val spacing = 12

    private fun columns(shelfWidthDp: Int, fontScale: Float = 1f): List<Int> = with(density) {
        with(ShelfColumns.of(shelfWidthDp.dp, fontScale)) {
            calculateCrossAxisCellSizes(
                availableSize = shelfWidthDp - gutter * 2,
                spacing = spacing,
            )
        }
    }

    @Test
    fun theListPaneOfATabletFitsMoreThanOneCover() {
        // The frame: 1280 x 576 dp, a ~380 dp list pane, one cover, most of the pane empty.
        val sizes = columns(380)

        assertTrue("a 380 dp pane drew ${sizes.size} column(s)", sizes.size > 1)
    }

    @Test
    fun aPaneIsMeasuredOnItsOwnWidthAndNotTheWindows() {
        // The defect in one line, at Material's own default list-pane width. Asking the
        // 1280 dp window gave the 158 dp tier, and 320 dp of content room then fits exactly
        // one 168 dp cover with 170 dp of pane beside it.
        assertEquals(2, columns(360).size)
        val asIfItAskedTheWindow = with(density) {
            with(ShelfColumns.of(1280.dp, 1f)) {
                calculateCrossAxisCellSizes(360 - gutter * 2, spacing)
            }
        }
        assertEquals(1, asIfItAskedTheWindow.size)
    }

    @Test
    fun aPhoneIsUnchanged() {
        // 411 dp: window and shelf are the same thing, so nothing about this window moves.
        assertEquals(3, columns(411).size)
    }

    @Test
    fun aFullWidthTabletShelfKeepsItsWideTier() {
        // Wide room still takes the wide tier, and every column stops at the readable cap.
        val sizes = columns(1280)

        assertEquals(7, sizes.size)
        assertTrue("a column was ${sizes.max()} dp", sizes.all { it <= 168 })
    }

    @Test
    fun theAccessibilityStepStillCostsAColumn() {
        assertTrue(columns(380, fontScale = 1.5f).size < columns(380).size)
    }
}
