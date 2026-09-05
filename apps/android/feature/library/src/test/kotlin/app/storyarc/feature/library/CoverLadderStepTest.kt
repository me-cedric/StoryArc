package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The five surfaces in `:feature:library` that state a cover width of their own all take the
 * ladder's accessibility step.
 *
 * `design.md` §4 tabulated eight surfaces off the rule on 2026-09-05 — three remote-browse
 * grids and these five. The grids now ask `rememberCoverColumns()` and are pinned by `:app`'s
 * `ShelvesAskOneRuleTest`; these five keep a width of their own for a reason each states in
 * its KDoc, and what they had all missed was the step. None of them read the font scale, so a
 * reader at font scale 2.0 saw the library grid widen 104 → 146 dp while the series shelf a
 * tap away stayed at 108, the shelf lattice at 150, the list thumbnail at 44.
 *
 * Each width is a pure function of the font scale, so this suite can assert the arithmetic
 * without a window — the same reach `HomeCoverWidthTest` has into Home. The step is
 * `steppedForFontScale`'s, which `CoverMinimumWidthTest` owns; what is asserted here is that
 * every one of these five actually calls it, at the boundary and either side of it.
 */
class CoverLadderStepTest {

    /** The widths as written, unchanged at every ordinary text size. */
    @Test
    fun `every surface keeps its own width at an ordinary text size`() {
        assertEquals(108.dp, seriesCellWidth(1f))
        assertEquals(92.dp, coverOptionMinimumWidth(1f))
        assertEquals(140.dp, coverOptionMaximumWidth(1f))
        assertEquals(150.dp, shelfLatticeMinimumWidth(1f))
        assertEquals(220.dp, shelfLatticeMaximumWidth(1f))
        assertEquals(44.dp, listThumbnailWidth(1f))
        assertEquals(140.dp, catalogueGroupCoverWidth(1f))
    }

    /**
     * And each takes the step, by 1.4, rounded to whole dp.
     *
     * These are the assertions the change exists for: a 108 here at 1.3 means the series
     * shelf is back to reading nothing, and the same for each of the others.
     */
    @Test
    fun `every surface takes the accessibility step`() {
        assertEquals(151.dp, seriesCellWidth(1.3f))
        assertEquals(129.dp, coverOptionMinimumWidth(1.3f))
        assertEquals(196.dp, coverOptionMaximumWidth(1.3f))
        assertEquals(210.dp, shelfLatticeMinimumWidth(1.3f))
        assertEquals(308.dp, shelfLatticeMaximumWidth(1.3f))
        assertEquals(62.dp, listThumbnailWidth(1.3f))
        assertEquals(196.dp, catalogueGroupCoverWidth(1.3f))
    }

    /**
     * The boundary is 1.3, where Android's ordinary Font size slider stops — the first scale
     * that steps, and not one before. A width the same either side of it is a surface that
     * reads the setting and ignores it.
     */
    @Test
    fun `the step lands on the accessibility boundary and not before`() {
        assertEquals(108.dp, seriesCellWidth(1.29f))
        assertEquals(92.dp, coverOptionMinimumWidth(1.29f))
        assertEquals(150.dp, shelfLatticeMinimumWidth(1.29f))
        assertEquals(44.dp, listThumbnailWidth(1.29f))
        assertEquals(140.dp, catalogueGroupCoverWidth(1.29f))
    }

    /** A step, not a scale: 2.0 is the same one step 1.3 is, because a column is a step. */
    @Test
    fun `the largest text size takes the same single step`() {
        assertEquals(151.dp, seriesCellWidth(2f))
        assertEquals(129.dp, coverOptionMinimumWidth(2f))
        assertEquals(210.dp, shelfLatticeMinimumWidth(2f))
        assertEquals(62.dp, listThumbnailWidth(2f))
        assertEquals(196.dp, catalogueGroupCoverWidth(2f))
    }
}
