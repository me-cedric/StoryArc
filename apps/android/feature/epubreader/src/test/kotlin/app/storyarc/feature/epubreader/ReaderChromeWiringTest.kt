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
 * **So this test reads the source text, and that is a deliberate second choice.** The honest
 * test is an instrumented one — compose the activity's chrome and measure the surface, the
 * way `ThemeSheetSemanticsTest` composes `StoryArcTheme` directly, and this module already
 * declares the dependencies for it. What the repository has no gate for is *running* one.
 * `.github/workflows/android.yml` does boot an emulator, on a push to `main`, and the script
 * it runs there is `:core:format:connectedDebugAndroidTest` and nothing else — so this
 * module's four `androidTest` classes execute only when somebody runs them by hand, while
 * the unit gate runs on every pull request. The instrumented measurement is still the test
 * worth adding, on the day that one script line names this module too. Until then a guard
 * that runs beats a better one that does not.
 *
 * What a `RuntimeShader`-free JVM can do is read the file and refuse the one edit that
 * reintroduces the defect. It is a tripwire, not a proof: it says the argument is spelled
 * correctly, never that the pixels came out black. `scripts/line-cap.mjs` is the same kind
 * of gate for the same kind of reason. Delete this the day an instrumented test measures the
 * reader's chrome on a device.
 */
class ReaderChromeWiringTest {

    /**
     * The activity's source, at the path the module's build script hands to the test JVM.
     *
     * Deliberately not discovered. Walking up from the working directory leaves the module:
     * this repository nests agent worktrees at `.claude/worktrees/<name>/`, so the walk
     * climbs out of the worktree under test and reads the parent checkout's copy — a guard
     * passing or failing on source that was never built. [MODULE_DIRECTORY] is set from
     * `projectDir` in `build.gradle.kts`, which is the module being built by construction,
     * and the file is declared an input of the test task there — a `Test` task otherwise
     * depends on its classpath rather than on the sources behind it, so nothing would tie
     * this task's up-to-date check to what it reads. `:core:format` hands its fixture corpus
     * over the same way.
     *
     * Missing is a failure rather than a skip: a guard that cannot find what it guards has
     * to say so, or it passes forever after the file is renamed.
     */
    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, ACTIVITY_SOURCE)
        if (!file.isFile) {
            error("$ACTIVITY_SOURCE is not under ${module.absolutePath} — has it moved?")
        }
        file.readText()
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

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val ACTIVITY_SOURCE =
            "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt"
    }
}
