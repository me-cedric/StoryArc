package app.storyarc

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every cover-shaped cell of the reader's own publications asks one composable for its well,
 * and none of them draws a cover with a construct that has no else branch.
 *
 * This reads Kotlin source, for the reason `ShelvesAskOneRuleTest` sets out beside it: the
 * property worth pinning is one of the **call sites**. `:feature:library`'s `CoverlessWellTest`
 * already owns what a well draws — and it would keep passing for as long as the Downloads
 * shelf, a module away, drew nothing at all, because a test of a composable cannot see who
 * declined to call it. That is not hypothetical; it is exactly the state this repository was in
 * this morning, with the library's well written and three shelves without one.
 *
 * `:app` declares neither Robolectric nor a Compose test rule in `testImplementation`, so the
 * only suites that could compose `OnDeviceCover` are instrumented and do not run in the unit
 * gate. `app/build.gradle.kts` declares every `.kt` under the Gradle root as an input of this
 * task, which is what makes a source-reading test re-run on an incremental build instead of
 * going quietly stale — that block's own comment explains how it was reproduced.
 *
 * What it deliberately does **not** assert is that every cover in the app draws this well.
 * Four do not, on purpose, and `CoverlessWell.kt` names all four with the reason: a publication
 * page's hero draws a book glyph and no title, and three remote-browsing surfaces stand for an
 * OPDS entry or a Kavita series rather than a `Publication`. Adding one of those here without
 * converting it would fail rather than pass, which is the intended shape of that gap.
 */
class ShelvesDrawOneWellTest {

    /**
     * The four cover-shaped cells that hold a `Publication` of the reader's own.
     *
     * One of them — `CoverGrid` — had a well, and it is where the argument for having one was
     * written. The other three had none, and the difference between "the library" and "every
     * other shelf" was invisible to every automated check this project runs.
     */
    private val wells = listOf(
        "app/src/main/kotlin/app/storyarc/DownloadsParts.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/CoverGrid.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/HomeCards.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/DetailSeriesShelf.kt",
    )

    @Test
    fun `every publication cell asks the shared well`() {
        for (well in wells) {
            assertTrue(
                "$well draws a coverless cell without asking CoverlessWell",
                read(well).contains("CoverlessWell("),
            )
        }
    }

    /**
     * And none of them reaches for `?.let` to draw its artwork.
     *
     * This is the defect's actual shape, not a proxy for it. `cover?.let { Image(…) }` reads as
     * a null check and is not one: it has no else branch and cannot be given one, so the case
     * where a publication has no artwork is not handled, it is *unwritten*. All three broken
     * shelves were written that way, and all three passed every review — the missing branch is
     * not visible as an omission, because there is no empty block to notice.
     *
     * An `if`/`else` cannot hide the same mistake: the else is either there and drawing
     * something, or absent and obvious.
     */
    @Test
    fun `no publication cell draws its artwork with a construct that has no else branch`() {
        for (well in wells) {
            assertTrue(
                "$well draws an Image inside a ?.let, which has no branch for no artwork",
                !COVER_INSIDE_LET.containsMatchIn(read(well)),
            )
        }
    }

    /**
     * And the well's layout is written down once.
     *
     * A shelf that re-copied the pair of text roles would satisfy both tests above and still be
     * the defect they exist for — four copies of one view is how this started. The two roles
     * appear together in exactly one file, the one that owns the well.
     */
    @Test
    fun `only the design system states the well's two text roles`() {
        // Assembled rather than written out, so this file does not match its own assertion —
        // which it did on the first run, and which is why `ShelvesAskOneRuleTest` assembles too.
        val roles = listOf("titleSmall", "labelSmall").map { "typography.$it" }
        val statedIn = androidRoot.walkTopDown()
            // Gradle's own output holds generated and copied sources, and none of it is
            // something a reviewer could fix.
            .onEnter { it.name != "build" }
            .filter { it.isFile && it.extension == "kt" }
            .filter { file -> roles.all { file.readText().contains(it) } }
            .map { it.name }
            .toSortedSet()
        assertEquals(sortedSetOf("CoverlessWell.kt"), statedIn)
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        assertTrue("$path has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /**
         * `cover?.let { Image(` — the artwork drawn inside a scope function, across the line
         * break Kotlin's formatter puts there.
         */
        val COVER_INSIDE_LET = Regex("""\?\.let\s*\{\s*Image\(""")

        /**
         * `apps/android`, found rather than hardcoded.
         *
         * Gradle runs a unit test with the module directory as its working directory, so the
         * walk starts inside `:app` and stops at the first ancestor holding the settings file.
         * Nothing above `apps/android` has one — the repository's build is pnpm's.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
