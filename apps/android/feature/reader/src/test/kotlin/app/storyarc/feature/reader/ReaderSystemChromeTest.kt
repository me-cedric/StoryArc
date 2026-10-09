package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * What the reader takes from the device while it is open, and gives back on the way out.
 *
 * `comic-reader`, *Screen stays awake*:
 *
 * > **THEN** the screen does not auto-lock while a page is visible, and normal locking
 * > resumes on leaving
 *
 * `comic-reader`, *Orientation lock*:
 *
 * > **THEN** it stays locked for the reader only, and the rest of the app follows the device
 *
 * **Both scenarios are one rule and the same failure.** Each takes a device-wide setting for
 * the length of a reading session, and each is wrong in the same way if it is not handed
 * back: a reader who leaves the publication and finds their phone will not sleep, or will not
 * rotate, has been left worse off by a reader they closed. Neither half can be seen in a
 * screenshot, and neither is something a reader reports as a reader bug.
 *
 * **Why it reads the source text.** `keepScreenOn` is a property of a live view and
 * `requestedOrientation` of a live activity; both need a device, and this module has no
 * instrumented test source set. `ReaderChromeTest` is the same choice made for the same
 * reason and carries the same warning: this is a tripwire, not a proof. It says the effect
 * writes the value back on the way out; it never says the device slept.
 * `ReaderSystemChromeTests` is the iOS half.
 */
class ReaderSystemChromeTest {

    /**
     * The screen's source, at the path the module's build script hands to the test JVM.
     *
     * Comments are stripped before anything is matched: this file explains both rules in its
     * own words, and a guard that found `keepScreenOn` in a paragraph about keeping the screen
     * on would be measuring the documentation.
     */
    private val code: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SCREEN_SOURCE)
        if (!file.isFile) {
            error("$SCREEN_SOURCE is not under ${module.absolutePath} — has the screen moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(readerScreenSource(module), "")
        withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    @Test
    fun `the screen is held awake while the reader is open and released on the way out`() {
        assertTrue(
            "The reader no longer stops the screen locking. `comic-reader`: \"the screen does" +
                " not auto-lock while a page is visible\". A long look at one page is reading," +
                " not idling.",
            code.contains("view.keepScreenOn = true"),
        )
        assertTrue(
            "The reader no longer lets the screen lock again on the way out. `comic-reader`:" +
                " \"normal locking resumes on leaving\". A phone that stopped sleeping and was" +
                " never told it may again is the worse half of this scenario, and it outlives" +
                " the reader that caused it.",
            code.contains("onDispose { view.keepScreenOn = false }"),
        )
    }

    @Test
    fun `the orientation lock is the reader's own and is given back on the way out`() {
        assertTrue(
            "The reader no longer pins the activity when it is asked to. `comic-reader`" +
                " requires a locked reader to stay \"locked for the reader only\", and" +
                " SCREEN_ORIENTATION_LOCKED is what holds the way up it already has.",
            code.contains("ActivityInfo.SCREEN_ORIENTATION_LOCKED"),
        )
        assertTrue(
            "The reader no longer hands the orientation back on the way out. `comic-reader`:" +
                " \"the rest of the app follows the device\". An activity pinned by the reader" +
                " and never unpinned holds the whole app there, and nothing outside the reader" +
                " offers a way to undo it.",
            code.contains(
                "onDispose { activity?.requestedOrientation =" +
                    " ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }",
            ),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        const val SCREEN_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt"
    }
}
