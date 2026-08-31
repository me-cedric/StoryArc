package app.storyarc

import androidx.compose.ui.unit.Density
import app.storyarc.core.designsystem.grid.BoundedAdaptive
import app.storyarc.core.designsystem.grid.coverMaximumWidth
import app.storyarc.core.designsystem.grid.coverMinimumWidth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Downloads shelf and the library shelf answer the same window with the same columns.
 *
 * They did not. The rule lived in `:feature:library` behind `internal`, so `:app` could not
 * call it and kept a copy — and the copy had drifted twice over. It ignored the reader's font
 * scale, so at an accessibility text size the Downloads shelf held 104 dp columns while the
 * library shelf widened to 146; and it asked for `GridCells.Adaptive`, which has no upper
 * bound, so on a tablet its covers stretched past the 168 dp the library's stop at. Two
 * shelves onto one library, laying out differently. iOS had the identical divergence in
 * `OnDeviceShelf`, where Apple's accessibility audit reported it as five clipped labels.
 *
 * **The two shelves now literally call one function** — `rememberCoverColumns` in
 * `:core:designsystem` — and both grids take the same `gutter` on each side and the same `md`
 * between columns, so the available width they divide is the same number as well. There is no
 * longer a second implementation for this file to compare the first against.
 *
 * So this guards the **call sites**, not the arithmetic. The counts below are what a reader is
 * shown on both destinations, asserted from `:app`, which is the module that held the copy: a
 * shelf here that stopped asking — a fourth copy of the ladder, a bare `GridCells.Adaptive`, a
 * grid that forgot the font scale — would have to reproduce this whole table before it could
 * slip past. `:core:designsystem`'s `CoverMinimumWidthTest` owns the widths themselves; this
 * owns the agreement.
 */
class ShelfColumnsAgreeTest {

    /**
     * `design.md` §4's whole ladder, either side of both of Material's breakpoints.
     *
     * 599 dp gets four narrow columns and 600 dp gets three wide ones: a window that grew by
     * one dp holds *fewer*, larger covers, which is the tier doing its job rather than a bug.
     */
    @Test
    fun `both shelves lay out these columns at an ordinary text size`() {
        assertEquals(2, shelfColumns(360, ORDINARY))
        assertEquals(4, shelfColumns(599, ORDINARY))
        assertEquals(3, shelfColumns(600, ORDINARY))
        assertEquals(5, shelfColumns(839, ORDINARY))
        assertEquals(4, shelfColumns(840, ORDINARY))
        assertEquals(8, shelfColumns(1400, ORDINARY))
    }

    /**
     * And these at the text size that exposed the drift. Every tier steps one column
     * narrower — except the 360 dp phone, which was already at two and has nothing to give.
     */
    @Test
    fun `both shelves lay out these columns at an accessibility text size`() {
        assertEquals(2, shelfColumns(360, ACCESSIBILITY))
        assertEquals(3, shelfColumns(599, ACCESSIBILITY))
        assertEquals(2, shelfColumns(600, ACCESSIBILITY))
        assertEquals(4, shelfColumns(839, ACCESSIBILITY))
        assertEquals(3, shelfColumns(840, ACCESSIBILITY))
        assertEquals(5, shelfColumns(1400, ACCESSIBILITY))
    }

    /**
     * Neither shelf lets a cover past the cap, at any width, at either text size.
     *
     * This is the clause `GridCells.Adaptive` could not hold and the Downloads shelf was
     * therefore missing: its single stretched column had no upper bound at all, and a narrow
     * window filled itself edge to edge with one cover.
     */
    @Test
    fun `neither shelf stretches a cover past the readable maximum`() {
        for (fontScale in listOf(ORDINARY, ACCESSIBILITY)) {
            val cap = coverMaximumWidth(fontScale).value.toInt()
            for (width in 200..2400 step 7) {
                for (column in columnWidths(width, fontScale)) {
                    assertTrue("a $width dp window drew a $column dp cover, cap $cap", column <= cap)
                }
            }
        }
    }

    /** How many covers a window this wide holds, on either destination. */
    private fun shelfColumns(windowWidthDp: Int, fontScale: Float): Int =
        columnWidths(windowWidthDp, fontScale).size

    /**
     * The grid both shelves build, measured.
     *
     * `rememberCoverColumns` is a composable and this is a plain JVM test, so the two bounds
     * are read the way it reads them. Density 1, so a dp is a pixel. The window loses `gutter`
     * on each side to the grid's content padding and `md` between columns — the numbers both
     * grids are written with, and the reason their answers can be one answer.
     */
    private fun columnWidths(windowWidthDp: Int, fontScale: Float): List<Int> {
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
        /** Android's Font size slider stops at 1.3 outside accessibility settings. */
        const val ORDINARY = 1f
        const val ACCESSIBILITY = 1.5f

        /** `layout.json`: `gutter` 20 each side, `md` 12 between columns. */
        const val GUTTER = 20
        const val COLUMN_SPACING = 12
    }
}
