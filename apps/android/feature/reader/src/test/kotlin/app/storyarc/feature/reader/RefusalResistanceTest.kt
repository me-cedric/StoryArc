package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A refused discrete turn gives a little and springs back (task 8.11, D13).
 *
 * `page-transitions` "Turning at a boundary": "the page resists with a bounded rubber-band
 * and returns". The rule is asserted directly; the wiring is read from the source, because a
 * host test cannot watch an offset animate.
 */
class RefusalResistanceTest {

    @Test
    fun `left-to-right gives to the right, the way the missing page would push it`() {
        assertEquals(
            RefusalResponse.Nudge(RefusalResponse.REACH_DP),
            RefusalResponse.of(reduceMotion = false, isRightToLeft = false, scrolls = false),
        )
    }

    @Test
    fun `right-to-left gives to the left`() {
        assertEquals(
            RefusalResponse.Nudge(-RefusalResponse.REACH_DP),
            RefusalResponse.of(reduceMotion = false, isRightToLeft = true, scrolls = false),
        )
    }

    @Test
    fun `reduce motion dims instead of moving the page`() {
        assertEquals(
            RefusalResponse.Dim,
            RefusalResponse.of(reduceMotion = true, isRightToLeft = false, scrolls = false),
        )
    }

    @Test
    fun `a scroll shows nothing more than its own overscroll`() {
        assertNull(RefusalResponse.of(reduceMotion = false, isRightToLeft = false, scrolls = true))
    }

    @Test
    fun `the refusal branch plays the response over the page surface`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this through Gradle.")
        val screen = File(module, "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt").readText()
        val refusal = screen.indexOf("haptics.play(StoryArcFeedback.REFUSAL)")
        val play = screen.indexOf("scope.launch { resistance.play(response) }")
        assertTrue("A refused turn no longer plays the resistance beside its haptic.", refusal in 0 until play)
        assertTrue(
            "The response no longer reads Reduce Motion, the direction and the mode.",
            screen.contains(
                "val response = RefusalResponse.of(reduceMotion, isRightToLeft, paging is Paging.Scrolled)",
            ),
        )
        assertTrue(
            "The page surface no longer draws where the resistance puts it.",
            screen.contains("Box(Modifier.fillMaxSize().then(resistance.modifier), contentAlignment = Alignment.Center)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
