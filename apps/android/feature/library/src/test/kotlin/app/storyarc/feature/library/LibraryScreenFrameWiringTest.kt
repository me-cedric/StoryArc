package app.storyarc.feature.library

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * `close-the-audited-gaps` 25.2: the screen is built from the frame and the bar the landscape
 * test drives. `LibraryScreen` needs a view model to show a shelf, so a JVM test cannot compose
 * it. This reads its source, as `HomeHeroResumeWiringTest` does, and is a tripwire and not a
 * proof: it fails when the screen stops using them.
 */
class LibraryScreenFrameWiringTest {

    private val screen: String by lazy {
        val module = System.getProperty("storyarc.library.projectDir")?.let(::File)
            ?: error("storyarc.library.projectDir is unset. Run this through Gradle.")
        File(module, "src/main/kotlin/app/storyarc/feature/library/LibraryScreen.kt").readText()
    }

    @Test
    fun `the strip above the shelf is drawn in the frame that scrolls it away`() {
        assertTrue("The screen does not draw LibraryFrame.", screen.contains("LibraryFrame(compactHeight,"))
        assertTrue("The strip is not in the frame's header.", screen.contains("header {"))
    }

    @Test
    fun `the bar and the scroll behaviour follow the window height`() {
        assertTrue(
            "The bar is not told the window is short.",
            screen.contains("compactHeight = compactHeight"),
        )
        assertTrue(
            "The scroll behaviour does not follow the window height.",
            screen.contains("if (compactHeight) {\n        TopAppBarDefaults.enterAlwaysScrollBehavior()"),
        )
    }
}
