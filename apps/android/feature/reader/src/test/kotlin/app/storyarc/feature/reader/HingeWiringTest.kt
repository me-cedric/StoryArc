package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the comic reader draws its pages through
 * [app.storyarc.core.designsystem.navigation.HingeSpread] and
 * [app.storyarc.core.designsystem.navigation.HingeInsetPage], with a hinge measured from the
 * page surface.
 *
 * `HingeSlotsTest` asserts the layout itself. A `Posture` from a folded device is not a
 * Robolectric shadow this repository uses, so this reads the call sites, in the manner of
 * `CurlSheetWiringTest`. It asserts the calls are written, not that a device folds correctly.
 */
class HingeWiringTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val readerScreen: String by lazy {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt")
        if (!file.isFile) error("ReaderScreen.kt is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    /** Just `Page()`'s own body, bracket-matched so a call elsewhere in the file cannot pass this. */
    private fun pageBody(): String {
        val signature = readerScreen.indexOf("fun Page(display: Int, stitch: ScrollAxis? = null) {")
        check(signature >= 0) { "ReaderScreen.kt no longer declares Page(display, stitch) — has it moved?" }
        val open = readerScreen.indexOf('{', signature)
        var depth = 1
        var i = open + 1
        while (depth > 0) {
            when (readerScreen[i]) {
                '{' -> depth++
                '}' -> depth--
            }
            i++
        }
        return readerScreen.substring(open, i)
    }

    @Test
    fun `a lone page and a pair go through the hinge layouts`() {
        val body = pageBody()
        assertTrue(
            "Page() no longer draws a lone page through HingeInsetPage.",
            body.contains("HingeInsetPage(hingeSurface.hinge) { SinglePage("),
        )
        assertTrue(
            "Page() no longer draws a pair through HingeSpread.",
            body.contains("HingeSpread(hingeSurface.hinge) { half ->"),
        )
    }

    /**
     * A page inside a pager or a list moves with each frame of a swipe. Measured from that
     * page, the hinge split the page again on each frame and recomposed it on every device.
     */
    @Test
    fun `the hinge is measured from the page surface, not from a moving page`() {
        assertTrue(
            "The page surface no longer records its own place in the window.",
            readerScreen.contains("Modifier.fillMaxSize().then(hingeSurface.modifier)"),
        )
        assertTrue(
            "Page() measures its own position again, which moves with every frame of a swipe.",
            !pageBody().contains("positionInWindow") && !pageBody().contains("onGloballyPositioned"),
        )
    }

    @Test
    fun `the curl keeps a page off the hinge too`() {
        // Named by its coordinator rather than by the mode: `Paging.Curled` is the one the
        // curl gets, and the branch reads it that way so `CurlSurface` is smart-cast.
        assertTrue(
            "The curl no longer draws inside HingeInsetPage.",
            readerScreen.contains("if (paging is Paging.Curled) HingeInsetPage(hingeSurface.hinge) {"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
