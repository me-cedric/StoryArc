package app.storyarc.core.designsystem.control

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the component Material retired does not come back to `apps/android`.
 *
 * **This is the only thing that will ever say so.** Material 3 Expressive says the baseline
 * segmented button *"is no longer recommended"*, and Compose has not deprecated it: `javap`
 * over `material3-1.5.0-alpha26.aar` shows no `Deprecated` annotation on `SegmentedButton`
 * anywhere, so no warning, no lint check and no compiler error exists to be turned on. Two
 * call sites stood for as long as they existed with nothing pointing at them, and a third
 * file, `ThemeSheet.kt`, sat importing the API without calling it — because Kotlin does not
 * report an unused import either.
 *
 * So the guard is text over source, which is a tripwire rather than a proof: it says the
 * spelling is absent, never that the right component was drawn.
 * `ConnectedButtonGroupTest` beside it owns what the replacement actually does.
 *
 * **Main sources only, and comments stripped.** Two false positives, both real and both
 * found by running it. A test that asserts an absence has to contain the spelling it forbids
 * — this file does, and so does `:feature:library`'s `LibrarySearchBarTest`, which has
 * guarded the search bar against acquiring a segmented control since the scope chips landed;
 * scanning only `src/main/kotlin` keeps the guard off its own tail and off that one. And the
 * replacement's own KDoc says, in words, what it replaces — the most useful sentence in the
 * file, and the first thing this guard flagged. So it reads code with the comments removed,
 * the way `:feature:epubreader`'s `ThemeSheetTest` does. A retired component named in prose
 * is documentation; one named in an expression is the component.
 *
 * **It reads every module, and the wiring for that already existed.** The Android root is
 * handed over by this module's `build.gradle.kts` as `storyarc.android.rootDir`, and the same
 * build file declares every `src/main/**/*.kt` under it as a task input — put there for
 * [ArcStopsAreNotChromeTest], which sweeps the whole app for the same kind of reason. Both
 * halves matter: the root is handed over rather than discovered, because a walk that climbs
 * from the working directory escapes the checkout when worktrees are nested at
 * `.claude/worktrees/<name>/`; and without the input declaration this task would sit
 * UP-TO-DATE while `:feature:reader` gained a segmented button, since no sibling module's
 * sources are otherwise on this task's classpath — the dependency runs the other way.
 */
class NoSegmentedButtonsTest {

    /**
     * Every production Kotlin source in `apps/android`.
     *
     * Reached from the module directory the build script hands over, never discovered by
     * walking up from the working directory: this repository nests agent worktrees at
     * `.claude/worktrees/<name>/`, so a walk climbs out of the checkout under test and reads
     * the parent's copy of files that were never built here. `build` directories are pruned
     * rather than filtered, so a stale generated source cannot fail the guard.
     */
    private val sources: List<File> by lazy {
        val android = System.getProperty(ROOT_DIRECTORY)?.let(::File)
            ?: error(
                "$ROOT_DIRECTORY is unset. This test reads the Android app's own sources and" +
                    " will not go looking for them elsewhere — run it through Gradle" +
                    " (`pnpm gradle :core:designsystem:testDebugUnitTest`), which sets the" +
                    " property from the Android root directory.",
            )
        if (!File(android, "settings.gradle.kts").isFile) {
            error(
                "$ROOT_DIRECTORY is not the Android root — ${android.absolutePath} has no" +
                    " settings.gradle.kts.",
            )
        }
        android.walkTopDown()
            .onEnter { it.name != "build" }
            .filter { it.isFile && it.extension == "kt" }
            .filter { MAIN_SOURCES in it.invariantSeparatorsPath }
            .toList()
    }

    /** A guard over an empty list passes forever. */
    @Test
    fun `there are sources to sweep, across more than one module`() {
        assertTrue("No production Kotlin sources found under $MAIN_SOURCES", sources.size > 50)

        val modules = sources.mapNotNull { file ->
            file.invariantSeparatorsPath.substringBefore("/$MAIN_SOURCES", "").ifEmpty { null }
        }.toSet()
        assertTrue("Only ${modules.size} module tree was swept", modules.size > 4)
    }

    /**
     * The file's code, with every comment removed.
     *
     * Block comments first, then line comments, which is `ThemeSheetTest`'s own helper. A
     * `//` inside a string literal would be cut too; no source here has one, and a guard that
     * over-strips can only produce a false pass on a line it never sees, never a false
     * failure on a line it invents.
     */
    private fun code(file: File): String {
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        return withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    @Test
    fun `no segmented button is drawn anywhere in the app`() {
        val offenders = sources.mapNotNull { file ->
            val text = code(file)
            val found = RETIRED.filter { text.contains(it) }
            if (found.isEmpty()) null else "${file.name}: ${found.joinToString()}"
        }

        assertTrue(
            "The segmented button is back:\n  ${offenders.joinToString("\n  ")}\n" +
                "Material 3 Expressive says it \"is no longer recommended\" and names the" +
                " connected button group as its replacement, with the selected option marked" +
                " by a round-to-square shape change rather than by a fill. Nothing in the" +
                " build will tell you: `SegmentedButton` carries no deprecation at material3" +
                " 1.5.0-alpha26 and Kotlin does not warn on an unused import. Use" +
                " `ConnectedButtonGroup` from :core:designsystem. If a segmented control is" +
                " genuinely right somewhere, change this test and say why — the search scope" +
                " chips are the worked example of a control this replacement is *wrong* for.",
            offenders.isEmpty(),
        )
    }

    /**
     * The other direction, because an absence guard alone is satisfied by deleting both.
     *
     * Two call sites were replaced. If the count drops, either a control was removed on
     * purpose — in which case this number moves with it — or the replacement was quietly
     * reverted to something that is not a connected group at all.
     */
    @Test
    fun `the replacement is still drawn at both call sites`() {
        val callers = sources.filter { file ->
            val text = code(file)
            // The declaration is not a call site, and it is the one file that necessarily
            // contains both spellings.
            text.contains("$REPLACEMENT(") && !text.contains("fun $REPLACEMENT(")
        }

        assertTrue(
            "ConnectedButtonGroup is drawn in ${callers.size} file(s):" +
                " ${callers.map { it.name }}. Two were expected — the PDF sheet's tab" +
                " switcher and the theme axes' alignment picker. An absence guard on its own" +
                " is satisfied by deleting both controls; this is the other direction. If a" +
                " control was genuinely removed, move this number with it.",
            callers.size >= 2,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from Gradle's own `rootDir`. */
        const val ROOT_DIRECTORY = "storyarc.android.rootDir"
        const val MAIN_SOURCES = "src/main/kotlin"
        const val REPLACEMENT = "ConnectedButtonGroup"

        /**
         * Every spelling of the retired component.
         *
         * `SegmentedButton` alone would catch the two row variants and the defaults object as
         * substrings, but they are listed so the failure names which one came back. Not
         * listed, and deliberately: `SegmentedListItem` and `ListItemDefaults.segmentedShapes`
         * — a different API, current, and what Material asks for to group list rows. Neither
         * contains "SegmentedButton", so neither is caught by accident.
         *
         * **`material3.SegmentedButton` is the fifth entry because the four above missed the
         * residue this change had to clean by hand.** `ThemeSheet.kt` held three imports of
         * the retired API and called none of them, so a bare `import
         * androidx.compose.material3.SegmentedButton` with no call site passed every spelling
         * listed here. An import is how the component comes back: it compiles, it is what a
         * copied snippet brings with it, and the next author reads it as permission.
         */
        val RETIRED = listOf(
            "SingleChoiceSegmentedButtonRow",
            "MultiChoiceSegmentedButtonRow",
            "SegmentedButtonDefaults",
            "SegmentedButton(",
            "material3.SegmentedButton",
        )
    }
}
