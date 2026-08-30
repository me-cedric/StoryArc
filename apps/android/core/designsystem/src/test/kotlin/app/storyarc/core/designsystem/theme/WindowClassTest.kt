package app.storyarc.core.designsystem.theme

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
 * iOS's `WindowClassTests` asserts the same table against the same number.
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
    fun `A window at the threshold gets the rail, and one dp below it does not`() {
        assertFalse(StoryArcWindowClass.of(599).showsSidebar)
        assertTrue(StoryArcWindowClass.of(600).showsSidebar)
        assertEquals(StoryArcWindowClass.EXPANDED, StoryArcWindowClass.of(600))
    }

    @Test
    fun `A tablet-width window gets the rail`() {
        // 673 dp is a Pixel Fold unfolded, 800 a Pixel Tablet in portrait, 1280 in
        // landscape.
        assertEquals(StoryArcWindowClass.EXPANDED, StoryArcWindowClass.of(673))
        assertEquals(StoryArcWindowClass.EXPANDED, StoryArcWindowClass.of(800))
        assertEquals(StoryArcWindowClass.EXPANDED, StoryArcWindowClass.of(1280))
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
        assertEquals(StoryArcWindowClass.EXPANDED, unfolded)
        // And the same width always answers the same thing, whichever direction it
        // arrived from: unfolding then folding again lands back on the phone layout.
        assertEquals(folded, StoryArcWindowClass.of(374))
        assertEquals(unfolded, StoryArcWindowClass.of(673))
    }

    @Test
    fun `Exactly two classes, because there is exactly one layout decision`() {
        // A third class would need a third layout to justify it, and there is not one: a
        // window either has room for the rail or it does not.
        assertEquals(2, StoryArcWindowClass.entries.size)
        assertEquals(
            listOf(StoryArcWindowClass.EXPANDED),
            StoryArcWindowClass.entries.filter { it.showsSidebar },
        )
    }

    @Test
    fun `The breakpoint is the number iOS uses`() {
        // Stated rather than left implicit: the two apps are mirrors, and a threshold
        // that drifted on one of them would be a divergence nothing else would catch.
        assertEquals(600, StoryArcWindowClass.SIDEBAR_WIDTH_THRESHOLD_DP)
    }
}
