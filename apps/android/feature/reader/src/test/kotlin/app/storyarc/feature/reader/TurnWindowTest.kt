package app.storyarc.feature.reader

import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.isScroll
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which transition modes a change of display position counts frames for.
 *
 * `page-transitions`'s *Frame budget* covers "any transition", and for months the instrument
 * reached the curl alone. This is the rule that says which of the others it reaches, held
 * outside the composition so that a test can call it.
 *
 * **No case below asserts a frame rate.** An emulator draws at its host's, and the rate is
 * read from the display at run time and reported, never asserted. See [FrameRunTest].
 *
 * iOS's `TurnWindowTests` asserts the same table, case for case.
 */
class TurnWindowTest {

    @Test
    fun `exactly the two containers that animate a turn and report no end open a run`() {
        val timed = PageTransition.entries.filter { it.turnWindowMillis != null }
        assertEquals(listOf(PageTransition.SLIDE, PageTransition.FAST_FADE), timed)
    }

    @Test
    fun `the curl counts its own frames so its position opens nothing`() {
        assertNull(PageTransition.PAGE_CURL.turnWindowMillis)
    }

    @Test
    fun `a scroll has no discrete turn so its position opens nothing`() {
        for (mode in PageTransition.entries.filter { it.isScroll }) {
            assertNull(mode.turnWindowMillis)
        }
    }

    /**
     * A window shorter than the animation it covers stops counting before the turn ends,
     * which is where a late frame is most likely. The cross-dissolve is the one animation
     * length this module states, so it is the floor every window has to clear.
     */
    @Test
    fun `a window outlasts the animation it has to cover`() {
        for (window in PageTransition.entries.mapNotNull { it.turnWindowMillis }) {
            assertTrue("$window ms does not outlast a $FADE_MILLIS ms fade", window > FADE_MILLIS)
        }
    }
}
