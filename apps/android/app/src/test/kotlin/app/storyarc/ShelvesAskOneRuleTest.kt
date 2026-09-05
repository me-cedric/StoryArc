package app.storyarc

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every shelf of the reader's own publications asks one function for its columns, and none of
 * them restates the ladder.
 *
 * This reads Kotlin source, which wants justifying. The thing worth pinning here is a property
 * of the **call sites**, not of any arithmetic: `:core:designsystem`'s `CoverMinimumWidthTest`
 * already owns the widths, and it kept passing for as long as the Downloads shelf was building
 * its own `GridCells.Adaptive` a module away, because a test of a function cannot see who
 * declined to call it. `rememberCoverColumns` is `@Composable`, and neither `:app` nor
 * `:feature:library` declares Robolectric or a Compose test rule in `testImplementation` — the
 * only suites that could compose it are instrumented, which do not run in the unit gate. So
 * the honest reach is the source itself. It is cheap, and it names the rule it enforces.
 *
 * Reading files Gradle does not know about is how a source-reading test goes quietly stale:
 * `:app`'s classpath does not carry another module's *test* sources, so appending the ladder
 * to one of those left `:app:testDebugUnitTest` UP-TO-DATE with the third assertion violated.
 * `app/build.gradle.kts` now declares every `.kt` under the Gradle root as an input of this
 * task, which is what makes "it fails the moment a shelf stops asking" true on an incremental
 * run and not only on a clean one.
 *
 * What it deliberately does **not** assert is that the shelves show the same number of
 * columns. They cannot, and a test saying so would be asserting something untrue of the app:
 * on a tablet the library renders inside the list pane of a `ListDetailPaneScaffold` while
 * Downloads is a full-width surface, so the same bounds are spent in very different rooms.
 * They do not *measure* the same thing either, and the second test insists on exactly that.
 * What is shared is the rule.
 */
class ShelvesAskOneRuleTest {

    /**
     * Every full shelf of covers that fills its window, and the whole of *that* list.
     *
     * `rememberCoverColumns` reads the **window**, which is the honest width for a surface
     * that fills it: for these four the window's width and the shelf's are one number.
     * `DownloadsDestination` was the one that held a copy of the ladder; the three
     * remote-browse grids drew `GridCells.Adaptive(140.dp)` — no ladder, no cap, no step —
     * until 2026-09-06, and are allowed here by name now that they ask the rule.
     *
     * This is not every cover in the app and must not be read as one. Five surfaces keep a
     * width of their own — `CatalogueGroups`, `ShelfCoverChoice`, `DetailSeriesShelf`,
     * `ShelvesScreen` and `CoverList` — because they are rows, sheets and thumbnails rather
     * than full shelves; `:feature:library`'s `CoverLadderStepTest` pins their accessibility
     * step by arithmetic, and `design.md` §4 tabulates all of them.
     */
    private val fullWidthShelves = listOf(
        "app/src/main/kotlin/app/storyarc/DownloadsDestination.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/CatalogueBrowserScreen.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/KavitaBrowserScreen.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/KavitaShelfScreens.kt",
    )

    /**
     * The one shelf ever drawn inside a pane: the library grid, in the list pane of a
     * `ListDetailPaneScaffold` on a tablet.
     *
     * A shelf drawn inside a pane wants the pane. Asking the window there took the widest
     * tier and drew one cover across a 360 dp list pane with 170 dp of it left empty — see
     * `ShelfColumns`, which hands the shelf's own width to the same two bound functions.
     */
    private val panedShelves = listOf(
        "feature/library/src/main/kotlin/app/storyarc/feature/library/CoverGrid.kt",
    )

    private val shelves: List<String> get() = fullWidthShelves + panedShelves

    /** Where the library shelf's own bounds are assembled. */
    private val bounds =
        listOf("feature/library/src/main/kotlin/app/storyarc/feature/library/ShelfColumns.kt")

    /**
     * A shelf that fills the window asks the window.
     *
     * Both shapes ask the design system for both bounds; what is forbidden is a shelf
     * answering for itself. This half pins the window-shaped shape to the shelves that are
     * entitled to it.
     */
    @Test
    fun `a full-width shelf asks the window for its columns`() {
        for (shelf in fullWidthShelves) {
            assertTrue(
                "$shelf lays covers out without asking the shared bounds",
                read(shelf).contains("columns = rememberCoverColumns()"),
            )
        }
    }

    /**
     * And a shelf drawn inside a pane asks its own width, never the window's.
     *
     * This test used to accept either shape for every shelf, which would have let the library
     * grid go back to reading the window and still pass. `9c1b50b9` made it measure the pane
     * and `ShelfColumnsTest` pins the arithmetic; this pins the call site from both sides —
     * the pane's width has to be asked, and the window's must not be, by name.
     */
    @Test
    fun `a shelf drawn inside a pane asks its own width and never the window's`() {
        for (shelf in panedShelves) {
            val source = read(shelf)
            assertTrue(
                "$shelf is drawn inside a pane and does not ask ShelfColumns for its own width",
                source.contains("ShelfColumns.of("),
            )
            assertFalse(
                "$shelf is drawn inside a pane and asks the window's width — the 1280 dp" +
                    " tablet that drew one cover across a 360 dp list pane, back again",
                source.contains("rememberCoverColumns()"),
            )
        }
    }

    /**
     * And the bounds themselves are never rebuilt out of raw numbers.
     *
     * `ShelfColumns` is allowed to construct a `BoundedAdaptive` because it constructs it
     * out of `coverMinimumWidth` and `coverMaximumWidth`; a shelf that passed two literals
     * would satisfy the test above and be the defect it exists for.
     */
    @Test
    fun `a shelf that builds its own bounds builds them out of the shared ones`() {
        for (shelf in shelves + bounds) {
            val source = read(shelf)
            if (!source.contains("BoundedAdaptive(")) continue
            assertTrue(
                "$shelf constructs bounds without asking coverMinimumWidth",
                source.contains("coverMinimumWidth(") && source.contains("coverMaximumWidth("),
            )
        }
    }

    /**
     * `GridCells.Adaptive` takes a lower bound and no upper one, so it cannot hold
     * `library-browsing`'s second clause — "cover size stays within the readable range
     * defined in the design tokens". A shelf reaching for it has silently dropped that
     * clause, which is what the Downloads shelf had done: 175 dp covers against a 168 dp
     * maximum, measured on the emulator.
     *
     * The open parenthesis is load-bearing: both files name the class in prose, explaining
     * which half of the scenario it cannot hold, and only a call constructs one.
     */
    @Test
    fun `no publication shelf builds its own adaptive columns`() {
        for (shelf in shelves) {
            assertTrue(
                "$shelf constructs a GridCells.Adaptive, which has no maximum",
                !read(shelf).contains("GridCells.Adaptive("),
            )
        }
    }

    /**
     * And nobody writes the ladder down twice.
     *
     * A shelf that re-copied `design.md` §4's three numbers would satisfy both tests above
     * and still be the defect they exist for — that is how the second copy got there in the
     * first place. The tiers appear together in exactly two files: the one that owns them,
     * and the one that tests them.
     */
    @Test
    fun `only the design system states the cover ladder`() {
        // Assembled rather than written out, so this file does not match its own assertion.
        val ladder = listOf(104, 132, 158).map { "$it.dp" }
        val statedIn = androidRoot.walkTopDown()
            // Gradle's own output holds generated and copied sources, and none of it is
            // something a reviewer could fix.
            .onEnter { it.name != "build" }
            .filter { it.isFile && it.extension == "kt" }
            .filter { file -> ladder.all { file.readText().contains(it) } }
            .map { it.name }
            .toSortedSet()
        assertEquals(sortedSetOf("CoverColumns.kt", "CoverMinimumWidthTest.kt"), statedIn)
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        assertTrue("$path has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /**
         * `apps/android`, found rather than hardcoded.
         *
         * Gradle runs a unit test with the module directory as its working directory, so the
         * walk starts inside `:app` and stops at the first ancestor holding the settings
         * file. Nothing above `apps/android` has one — the repository's build is pnpm's.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
