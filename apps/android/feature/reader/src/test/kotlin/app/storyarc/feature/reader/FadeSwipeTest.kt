package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Fast fade turns on a horizontal swipe (task 8.2).
 *
 * `page-transitions` "Turning the tap zones off": "every other trigger still turns pages —
 * swipe, keyboard, controller". Fast fade has no container, so before this a reader with the
 * tap zones off could turn only by the slider. The rule is asserted directly; the wiring is
 * read from the source, the trade `CurlSheetWiringTest` makes for the same reason.
 */
class FadeSwipeTest {

    @Test
    fun `a finger moving left asks for the next display position`() {
        assertEquals(1, fadeSwipeStep(travel = -THRESHOLD, threshold = THRESHOLD))
        assertEquals(1, fadeSwipeStep(travel = -500f, threshold = THRESHOLD))
    }

    @Test
    fun `a finger moving right asks for the previous display position`() {
        assertEquals(-1, fadeSwipeStep(travel = THRESHOLD, threshold = THRESHOLD))
    }

    @Test
    fun `a short drag turns nothing`() {
        assertEquals(0, fadeSwipeStep(travel = THRESHOLD - 1f, threshold = THRESHOLD))
        assertEquals(0, fadeSwipeStep(travel = 1f - THRESHOLD, threshold = THRESHOLD))
    }

    @Test
    fun `only the fade container carries the swipe`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this through Gradle.")
        val screen = readerScreenSource(module)
        val fade = screen.indexOf("is Paging.Indexed -> AnimatedContent(")
        val swipe = screen.indexOf("modifier = keyboard.fadeSwipe { turn(paging.current + it) },")
        assertTrue("The fade container is gone from ReaderScreen.kt.", fade >= 0)
        assertTrue(
            "The fade container no longer turns on a swipe.",
            swipe > fade && swipe < screen.indexOf("is Paging.Scrolled ->", fade),
        )
        assertEquals(
            "Slide's pager and the curl own their swipe; a second one would skip a page.",
            1,
            screen.split(".fadeSwipe").size - 1,
        )
    }

    private companion object {
        const val THRESHOLD = 100f
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
