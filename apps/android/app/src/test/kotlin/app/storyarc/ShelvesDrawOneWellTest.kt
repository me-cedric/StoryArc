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
 * property worth pinning is one of the **call sites**. A composition test cannot see who
 * declined to call the composable it composes — which is exactly the state this repository was
 * in this morning, with the library's well written and three shelves without one.
 *
 * What it is **not** is the only test of the four surfaces. Two of them are composed and
 * measured: `:app`'s `DownloadsCoverlessWellTest` draws the Downloads cell — the shelf the
 * defect was reported on, which until this round had nothing behind it but the substring check
 * below — and `:feature:library`'s `CoverlessWellTest` draws Home's and the well itself. A grep
 * that a name appears is a weak guard, and it is here for the two surfaces that have no other.
 *
 * `app/build.gradle.kts` declares every `.kt` under the Gradle root as an input of this task,
 * which is what makes a source-reading test re-run on an incremental build instead of going
 * quietly stale — that block's own comment explains how it was reproduced.
 *
 * What it deliberately does **not** assert is that every cover in the app draws this well.
 * Four do not, on purpose, and `CoverlessWell.kt` names all four with the reason: a publication
 * page's hero draws a book glyph and no title, and three remote-browsing surfaces stand for an
 * OPDS entry or a Kavita series rather than a `Publication`. Adding one of those here without
 * converting it would fail rather than pass, which is the intended shape of that gap.
 */
class ShelvesDrawOneWellTest {

    /**
     * The four cover-shaped cells that hold a `Publication` of the reader's own, and the format
     * each one asks the well to name.
     *
     * One of them — `CoverGrid` — had a well, and it is where the argument for having one was
     * written. The other three had none, and the difference between "the library" and "every
     * other shelf" was invisible to every automated check this project runs.
     *
     * The format is half the entry because it is the one parameter the four differ about, and
     * swapping any of them compiled and passed. Two of the four are pinned by a composition
     * test as well; these two — Downloads and the series shelf — are pinned here, and the shape
     * of the assertion is the honest one: it reads the argument at the call site.
     */
    private val wells = mapOf(
        "app/src/main/kotlin/app/storyarc/DownloadsParts.kt" to "publication.format",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/CoverGrid.kt" to
            "publication.format",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/HomeCards.kt" to
            "publication.format",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/DetailSeriesShelf.kt" to
            "publication.format",
    )

    @Test
    fun `every publication cell asks the shared well`() {
        for (well in wells.keys) {
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
        for (well in wells.keys) {
            assertTrue(
                "$well draws an Image inside a ?.let, which has no branch for no artwork",
                !COVER_INSIDE_LET.containsMatchIn(read(well)),
            )
        }
    }

    /**
     * And each one hands the well its own publication's format, not a stand-in.
     *
     * Task 16.8: every per-publication well now names the format rather than the title, which
     * the type system enforces (`CoverlessWell`'s publication overload takes a
     * `PublicationFormat`, not a nullable string, so there is no `null` left to pass by
     * mistake). What the compiler does not catch is a call that reaches for a constant or
     * another cell's format and still type-checks — `publication.format` is the one answer
     * that cannot be wrong for whichever publication the cell is drawing.
     */
    @Test
    fun `each cell names its own publication's format`() {
        val asked = wells.keys.associateWith { well ->
            FORMAT_ARGUMENT.find(read(well))?.groupValues?.get(1)
                ?: "no `format = …` argument found in a CoverlessWell( call"
        }
        assertEquals(wells, asked)
    }

    /**
     * And the well's layout is written down once.
     *
     * A shelf that re-copied its label role would satisfy the tests above and still be the
     * defect they exist for — four copies of one view is how this started. Task 16.8 dropped
     * the well's title role (`titleSmall`) entirely — the glyph stands in for it now — so this
     * walks for `labelSmall` alone, which the well still draws for the format or shelf name.
     *
     * The net is cover-shaped *and silent* files, not every file in the app: `labelSmall`
     * alone appears in nine of them, and one cover-shaped caller — `DetailSeriesShelf.kt` —
     * states it too, for its own `#3` caption rather than a copy of the well. Pairing
     * `StoryArcRadius.cover` with `clearAndSetSemantics` is what the well alone does among
     * them: a caption a reader is meant to hear is not drawn silent to begin with.
     *
     * `CoverlessWell.kt` itself is excluded rather than expected, because it draws the well's
     * *contents* and never the frame, so it has no cover radius of its own to match on. Its own
     * possession of the role is asserted directly instead.
     */
    @Test
    fun `only the design system states the well's label role`() {
        val role = "typography.labelSmall"
        val well = File(androidRoot, WELL)
        assertTrue("$WELL has moved; this test names it by path", well.isFile)
        assertTrue("the well no longer states $role", well.readText().contains(role))

        val copies = androidRoot.walkTopDown()
            // Gradle's own output holds generated and copied sources, and none of it is
            // something a reviewer could fix.
            .onEnter { it.name !in SKIPPED }
            .filter { it.isFile && it.extension == "kt" && it.name != well.name }
            .filter { file ->
                val text = file.readText()
                text.contains("StoryArcRadius.cover") &&
                    text.contains(role) &&
                    text.contains("clearAndSetSemantics")
            }
            .map { it.name }
            .toSortedSet()
        assertEquals(
            "a cover-shaped file restates the well's label role; if it is drawing a " +
                "coverless well it should ask CoverlessWell for one",
            emptySet<String>(),
            copies,
        )
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        assertTrue("$path has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /** Directories the well-copy walk does not enter. */
        val SKIPPED = setOf("build", "test", "androidTest")

        const val WELL =
            "core/designsystem/src/main/kotlin/app/storyarc/core/designsystem/cover/" +
                "CoverlessWell.kt"

        /**
         * `cover?.let { Image(` — the artwork drawn inside a scope function, across the line
         * break Kotlin's formatter puts there.
         */
        val COVER_INSIDE_LET = Regex("""\?\.let\s*\{\s*Image\(""")

        /**
         * The `format` argument of a `CoverlessWell(` call, on one line or across four.
         *
         * Deliberately unable to match nothing quietly: a call site whose shape this stops
         * matching reports "no `format = …` argument found" and fails, rather than passing
         * because it found no format to disagree with.
         */
        val FORMAT_ARGUMENT = Regex("""CoverlessWell\([^)]*?format = ([^,\n)]+)""")

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
