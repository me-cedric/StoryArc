package app.storyarc.feature.epubreader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the reader's chrome is actually handed the reader's choice.
 *
 * [ReaderAppearanceTest] pins the *rule* — which of the two answers takes the literal
 * appearance and which takes the resolved one. It cannot pin the *wiring*, and the wiring
 * is where the defect lived: `EpubReaderActivity` called `StoryArcTheme(appearance =
 * AppearanceMode.SYSTEM)`, so Settings › Appearance reached every screen in the app except
 * the one a reader spends the evening on. Reverting that one argument leaves
 * [ReaderAppearance] still built for the linked preset, so the file still compiles, lint
 * still passes, and a suite that only exercises `ReaderAppearance.of` stays green while the
 * defect is back.
 *
 * **So this test reads the source text, and that is a deliberate second choice.** The
 * honest test is an instrumented one — compose the activity's chrome and measure the
 * surface, the way `ThemeSheetSemanticsTest` composes `StoryArcTheme` directly. That needs
 * a booted emulator, which the unit gates do not have and CI does not run, so it would
 * guard nothing on the path the next hand actually takes. What a `RuntimeShader`-free JVM
 * *can* do is read the file and refuse the one edit that reintroduces the defect. It is a
 * tripwire, not a proof: it says the argument is spelled correctly, never that the pixels
 * came out black. `scripts/line-cap.mjs` is the same kind of gate for the same kind of
 * reason.
 *
 * Delete this the day an instrumented test measures the reader's chrome on a device. Until
 * then it is the only thing in the repository that fails when line 351 goes back.
 */
class ReaderChromeWiringTest {

    /**
     * The activity's source, located by walking up from wherever the test was launched.
     *
     * Gradle runs a unit test with the module directory as its working directory and an IDE
     * often does not, so both are tried at every level. Missing is a failure rather than a
     * skip: a guard that cannot find what it guards has to say so, or it passes forever
     * after the file is renamed.
     */
    private val source: String by lazy {
        val relative = "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt"
        var directory: File? = File("").absoluteFile
        while (directory != null) {
            listOf(relative, "apps/android/feature/epubreader/$relative")
                .map { File(directory, it) }
                .firstOrNull { it.isFile }
                ?.let { return@lazy it.readText() }
            directory = directory.parentFile
        }
        error("EpubReaderActivity.kt not found above ${File("").absolutePath}")
    }

    @Test
    fun `the chrome is themed with the appearance that was read, not a constant`() {
        val argument = Regex("""StoryArcTheme\(\s*appearance\s*=\s*([^,\n]+)""")
            .find(source)
            ?.groupValues
            ?.get(1)
            ?.trim()

        assertEquals(
            "The reader's chrome must be themed with what Settings › Appearance was read" +
                " into. Passing a literal here is the regression this test exists for:" +
                " `settings-and-about` requires an appearance to apply \"immediately across" +
                " the whole app without a restart\", and a book is not outside the app.",
            "appearance.chrome",
            argument,
        )
    }

    @Test
    fun `the reader decides no appearance of its own`() {
        // Stronger than the argument check and for one reason: it also catches the appearance
        // being smuggled back in beside the read one -- a fallback, a branch, a debug default.
        // The reader's job is to hand over what `ReaderAppearance` decided, never to name a
        // mode. If a legitimate need for the enum ever arrives here, that is the moment to
        // replace this file with the instrumented test its KDoc describes.
        assertTrue(
            "EpubReaderActivity names an AppearanceMode constant. The appearance the chrome" +
                " is drawn with belongs to Settings › Appearance and arrives through" +
                " ReaderAppearance; a mode written into this screen is the screen deciding" +
                " for the reader.",
            !source.contains("AppearanceMode"),
        )
    }
}
