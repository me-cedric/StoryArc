package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a tap, a key or a volume button turns the page the way Curl turns pages.
 *
 * `page-transitions` gives Curl one motion and the finger was the only thing that ran it:
 * an edge tap set the index, so the mode a reader chose for its fold looked like Fast fade
 * to everyone who taps. [curlStep] is the rule; the wiring that carries it is read as
 * source text below, for the reason `CurlSheetWiringTest` sets out — a `goTo` that springs
 * nothing cannot be asserted as a value without a frame clock.
 *
 * iOS's `CurlRequestTests` asserts the same table.
 */
class CurlRequestTest {

    @Test
    fun `a single reading-order step rolls the fold`() {
        assertEquals(1, curlStep(from = 3, to = 4, isRightToLeft = false, animate = true))
        assertEquals(-1, curlStep(from = 3, to = 2, isRightToLeft = false, animate = true))
    }

    @Test
    fun `right-to-left turns forward on the other display step`() {
        // The display order is reversed there, so display position 2 is the *next* page to
        // read and the fold has to roll forwards for it.
        assertEquals(1, curlStep(from = 3, to = 2, isRightToLeft = true, animate = true))
        assertEquals(-1, curlStep(from = 3, to = 4, isRightToLeft = true, animate = true))
    }

    @Test
    fun `a jump across the publication has no fold to roll`() {
        assertEquals(0, curlStep(from = 3, to = 40, isRightToLeft = false, animate = true))
        assertEquals(0, curlStep(from = 3, to = 3, isRightToLeft = false, animate = true))
    }

    @Test
    fun `a move the caller asked to make instantly cuts`() {
        // How the curl's own completed turn commits: the fold it would otherwise start is
        // the fold that has just finished, and rolling it again turns two pages for one
        // drag, then three for that one, and so on.
        assertEquals(0, curlStep(from = 3, to = 4, isRightToLeft = false, animate = false))
    }

    @Test
    fun `a tap past the last page curls onto the end screen, and only forward`() {
        // D10: a tap or a key past the last page opens the end screen "with the chosen
        // transition", which in Curl lifts the page off it.
        assertTrue(curlEndsAhead(from = 9, to = 10, isRightToLeft = false))
        assertTrue(curlEndsAhead(from = 0, to = -1, isRightToLeft = true))
        assertTrue(!curlEndsAhead(from = 0, to = -1, isRightToLeft = false))
    }

    // The wiring

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private fun sourceOf(name: String): String {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/$name")
        if (!file.isFile) error("$name is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    @Test
    fun `Curl gets a coordinator that springs, and Fast fade keeps the one that does not`() {
        val paging = sourceOf("Paging.kt")
        assertTrue(
            "Curl shares Fast fade's coordinator again, so a tap sets the index and the" +
                " page appears with no fold.",
            paging.contains("mode == PageTransition.PAGE_CURL -> {") &&
                paging.contains("Paging.Curled(index, progress, isRightToLeft)"),
        )
        assertTrue(
            "Paging.Curled no longer springs its progress before it commits the page.",
            paging.contains("progress.animateTo(targetValue = step.toFloat(), animationSpec = spring())"),
        )
    }

    @Test
    fun `the curl draws the progress its coordinator springs, not one of its own`() {
        // Two Animatables would mean a tap rolls a fold nothing draws.
        assertTrue(
            "CurledPages holds its own progress again, so a requested turn springs a value" +
                " the shader never reads.",
            !sourceOf("CurledPages.kt").contains("remember { Animatable(0f) }"),
        )
        assertTrue(
            "The curl is no longer handed its coordinator's progress.",
            sourceOf("CurlSurface.kt").contains("progress = paging.progress,"),
        )
    }

    @Test
    fun `a completed turn commits without asking for a second fold`() {
        assertTrue(
            "The curl's completed turn goes back through an animated move. It is called" +
                " after the fold has finished, so the move would roll the same page again.",
            sourceOf("ReaderScreen.kt").contains(
                "onTurn = { step -> scope.launch { paging.goTo(paging.current + step, animate = false) } },",
            ),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
