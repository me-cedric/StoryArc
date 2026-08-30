package app.storyarc.core.designsystem.theme

import androidx.window.core.layout.WindowSizeClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What decides the layout, and — more to the point — what does not.
 *
 * `native-experience` asks for a rail on a large screen, for a layout that "reflows
 * continuously" when the window is resized, and for a foldable to be followed through
 * folding, unfolding and the half-open posture. All three are the same question if the
 * only input is the window's width, and three different questions if a device check or a
 * posture check creeps in. These tests exist to keep it the first kind.
 *
 * Five classes rather than two since the tablet slice. iOS keeps its two, because SwiftUI
 * publishes two size classes and Material publishes five — divergence #4 in the design
 * direction's register. So these no longer mirror `WindowClassTests` case for case, and
 * the number they still share is 600.
 */
class WindowClassTest {

    @Test
    fun `A phone-width window gets one column`() {
        // 411 dp is a Pixel in portrait; 320 is the narrowest Android still supports.
        assertEquals(StoryArcWindowClass.COMPACT, StoryArcWindowClass.of(320))
        assertEquals(StoryArcWindowClass.COMPACT, StoryArcWindowClass.of(411))
        assertEquals(StoryArcWindowClass.COMPACT, StoryArcWindowClass.of(599))
    }

    @Test
    fun `A window at the rail threshold gets the rail, and one dp below it does not`() {
        assertFalse(StoryArcWindowClass.of(599).showsSidebar)
        assertTrue(StoryArcWindowClass.of(600).showsSidebar)
        assertEquals(StoryArcWindowClass.MEDIUM, StoryArcWindowClass.of(600))
    }

    @Test
    fun `Every one of Material's five breakpoints is a class of its own`() {
        // The whole point of the slice. Before it, all four of these were one answer, so
        // a portrait tablet and a landscape one laid out identically.
        assertEquals(StoryArcWindowClass.MEDIUM, StoryArcWindowClass.of(800))
        assertEquals(StoryArcWindowClass.EXPANDED, StoryArcWindowClass.of(840))
        assertEquals(StoryArcWindowClass.EXPANDED, StoryArcWindowClass.of(1199))
        assertEquals(StoryArcWindowClass.LARGE, StoryArcWindowClass.of(1200))
        assertEquals(StoryArcWindowClass.LARGE, StoryArcWindowClass.of(1599))
        assertEquals(StoryArcWindowClass.EXTRA_LARGE, StoryArcWindowClass.of(1600))
        assertEquals(StoryArcWindowClass.EXTRA_LARGE, StoryArcWindowClass.of(3840))
    }

    @Test
    fun `The five bounds are Material's own, not four numbers that look like them`() {
        // Read from `WindowSizeClass` rather than restated, so a breakpoint Material moved
        // fails here instead of drifting silently. `of` stays a pure function of an
        // integer, which is what keeps the ladder testable on a plain JVM.
        assertEquals(0, StoryArcWindowClass.COMPACT.lowerBoundDp)
        assertEquals(
            WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND,
            StoryArcWindowClass.MEDIUM.lowerBoundDp,
        )
        assertEquals(
            WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND,
            StoryArcWindowClass.EXPANDED.lowerBoundDp,
        )
        assertEquals(
            WindowSizeClass.WIDTH_DP_LARGE_LOWER_BOUND,
            StoryArcWindowClass.LARGE.lowerBoundDp,
        )
        assertEquals(
            WindowSizeClass.WIDTH_DP_EXTRA_LARGE_LOWER_BOUND,
            StoryArcWindowClass.EXTRA_LARGE.lowerBoundDp,
        )
    }

    @Test
    fun `A second pane arrives at expanded, not at the rail`() {
        // The bug the slice exists to fix, stated as an assertion: 600 dp is where the
        // rail arrives and 840 dp is where a detail can sit beside a list. Conflating the
        // two is what gave a 1400 dp landscape tablet a phone's layout.
        assertFalse(StoryArcWindowClass.of(839).showsTwoPanes)
        assertTrue(StoryArcWindowClass.of(840).showsTwoPanes)
        assertTrue(StoryArcWindowClass.of(600).showsSidebar)
        assertFalse(StoryArcWindowClass.of(600).showsTwoPanes)
    }

    @Test
    fun `The rail opens itself only where opening it costs the panes nothing`() {
        // The reader can open it at any width it is drawn at; this is only where it
        // starts open.
        assertFalse(StoryArcWindowClass.of(840).expandsRailByDefault)
        assertTrue(StoryArcWindowClass.of(1200).expandsRailByDefault)
        assertTrue(StoryArcWindowClass.of(1600).expandsRailByDefault)
    }

    @Test
    fun `A width that has not been measured yet is treated as narrow`() {
        // The first frame reports zero. The one-column layout fits every window and the
        // rail does not, so this is the safe way to be wrong for a frame.
        assertEquals(StoryArcWindowClass.COMPACT, StoryArcWindowClass.of(0))
    }

    @Test
    fun `Only the width is asked, so a fold is an ordinary resize`() {
        // The whole foldable requirement, stated as an assertion. A Pixel Fold is 374 dp
        // shut and 673 dp open; half-opened it is one of those two, because the hinge does
        // not change how wide the window is. Nothing here can tell which of the three
        // happened, which is the point — there is no posture branch to get wrong.
        val folded = StoryArcWindowClass.of(374)
        val unfolded = StoryArcWindowClass.of(673)
        assertEquals(StoryArcWindowClass.COMPACT, folded)
        assertEquals(StoryArcWindowClass.MEDIUM, unfolded)
        // And the same width always answers the same thing, whichever direction it
        // arrived from: unfolding then folding again lands back on the phone layout.
        assertEquals(folded, StoryArcWindowClass.of(374))
        assertEquals(unfolded, StoryArcWindowClass.of(673))
    }

    @Test
    fun `The ladder only ever climbs`() {
        // Each of the three answers is monotone in the width. A layout that switched on
        // and off again as a reader dragged a multi-window divider would be the defect
        // this shape is chosen to make unexpressible.
        val widths = (0..2000 step 7).toList()
        val classes = widths.map { StoryArcWindowClass.of(it) }
        assertEquals(classes.sorted(), classes)
        assertEquals(classes.map { it.showsSidebar }.sortedBy { it }, classes.map { it.showsSidebar })
        assertEquals(classes.map { it.showsTwoPanes }.sortedBy { it }, classes.map { it.showsTwoPanes })
    }

    @Test
    fun `The rail breakpoint is the number iOS uses`() {
        // Stated rather than left implicit: iOS keeps two size classes divided at 600 pt,
        // and that one number staying shared is what stops the two apps changing shape in
        // different places.
        assertEquals(600, StoryArcWindowClass.SIDEBAR_WIDTH_THRESHOLD_DP)
        assertEquals(840, StoryArcWindowClass.TWO_PANE_WIDTH_THRESHOLD_DP)
    }
}
