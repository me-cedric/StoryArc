package app.storyarc

import java.io.File
import org.junit.Assert.assertEquals
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
 * What it deliberately does **not** assert is that the two shelves show the same number of
 * columns. They cannot, and a test saying so would be asserting something untrue of the app:
 * on a tablet the library renders inside the list pane of a `ListDetailPaneScaffold` while
 * Downloads is a full-width surface, so the same bounds are spent in very different rooms.
 * They no longer *measure* the same thing either — see the first test. What is shared is the rule.
 */
class ShelvesAskOneRuleTest {

    /**
     * The two full grids of the reader's own publications, and the whole of *that* list.
     *
     * Both were written against `design.md` §4 and one of them held a copy of it. This is not
     * every cover in the app and must not be read as one: eight further surfaces state widths
     * of their own and take no accessibility step — `CatalogueBrowserScreen`,
     * `KavitaBrowserScreen`, `KavitaShelfScreens`, `CatalogueGroups`, `ShelfCoverChoice`,
     * `DetailSeriesShelf`, `ShelvesScreen` and `CoverList`. `design.md` §4 tabulates all
     * eight with what each states and how the list was arrived at. They are a live gap, not
     * one this file pretends is closed, and adding one here without converting it would fail
     * rather than pass.
     */
    private val shelves = listOf(
        "app/src/main/kotlin/app/storyarc/DownloadsDestination.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/CoverGrid.kt",
    )

    /** Where the library shelf's own bounds are assembled. */
    private val bounds =
        listOf("feature/library/src/main/kotlin/app/storyarc/feature/library/ShelfColumns.kt")

    /**
     * Two shapes, and the second is why there are two.
     *
     * `rememberCoverColumns` reads the **window**, which is what a full-width surface wants.
     * A shelf drawn inside a pane wants the pane, and asking the window there took the widest
     * tier and drew one cover across a 360 dp list pane with 170 dp of it left empty — see
     * `ShelfColumns`, which passes the shelf's own width to the same two bound functions.
     * What is pinned is that a shelf asks the design system for both bounds, whichever width
     * it hands them; what is still forbidden is a shelf answering for itself.
     */
    @Test
    fun `every publication shelf asks the shared rule for its columns`() {
        for (shelf in shelves) {
            val source = read(shelf)
            val asksTheWindow = source.contains("columns = rememberCoverColumns()")
            val asksItsOwnWidth = source.contains("ShelfColumns.of(")
            assertTrue(
                "$shelf lays covers out without asking the shared bounds",
                asksTheWindow || asksItsOwnWidth,
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
