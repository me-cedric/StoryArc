package app.storyarc.core.designsystem.cover

import app.storyarc.core.model.PublicationFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * What a cover-shaped cell with no artwork draws, and which surfaces still draw it.
 *
 * Task 16.8: the well drew the publication's **title**, repeating the name the screen around
 * it already stated — the player most of all, since nothing else there names the book twice.
 * iOS settled the identical complaint by drawing the format's own glyph and name instead; this
 * is Android's half, and it mirrors `CoverlessWellTests.swift` deliberately, so an audiobook
 * cannot be drawn as a book on one platform and correctly on the other.
 *
 * Two halves, for different reasons:
 *
 * - **The mapping** ([coverlessWellIcon], [coverlessShelfIcon]). Pure, so it needs no
 *   Robolectric and no composition — a `PublicationFormat` goes in and an `ImageVector` comes
 *   out, and every assertion below reads the vector's own `name` rather than rendering
 *   anything.
 * - **The reach.** Every surface that used to draw `CoverlessWell(title = …, format = …)`
 *   compiles only if it now calls one of the two overloads this file declares — which is
 *   most of this regression's own guard, since the old signature simply does not exist any
 *   more. What a type error cannot catch is a caller that compiles clean by reaching for the
 *   *wrong* overload — passing `publication.displayTitle` to the shelf overload's `name`
 *   instead of the format to the publication overload — which is the same defect in a
 *   different shape. That half is asserted over source text, the way
 *   `NoSegmentedButtonsTest` beside this file already does.
 */
class CoverlessWellTest {

    // MARK: - The mapping

    @Test
    fun `every comic container shares one glyph`() {
        val cbz = coverlessWellIcon(PublicationFormat.CBZ).name
        for (format in listOf(
            PublicationFormat.CBR,
            PublicationFormat.CB7,
            PublicationFormat.CBT,
            PublicationFormat.IMAGE_FOLDER,
        )) {
            assertEquals("$format should share CBZ's glyph", cbz, coverlessWellIcon(format).name)
        }
    }

    @Test
    fun `every audio container shares one glyph, and it is never a book`() {
        val m4b = coverlessWellIcon(PublicationFormat.M4B).name
        for (format in listOf(
            PublicationFormat.MP3,
            PublicationFormat.FLAC,
            PublicationFormat.OGG,
            PublicationFormat.AUDIO_FOLDER,
        )) {
            assertEquals("$format should share M4B's glyph", m4b, coverlessWellIcon(format).name)
        }
        assertTrue(
            "an audiobook's glyph reads as a book: $m4b",
            !m4b.contains("Book", ignoreCase = true) && !m4b.contains("Stories", ignoreCase = true),
        )
    }

    @Test
    fun `the four kinds a reader can open are told apart`() {
        val kinds = listOf(
            coverlessWellIcon(PublicationFormat.CBZ),
            coverlessWellIcon(PublicationFormat.EPUB),
            coverlessWellIcon(PublicationFormat.PDF),
            coverlessWellIcon(PublicationFormat.M4B),
        ).map { it.name }

        assertEquals("two of the four kinds share a glyph: $kinds", kinds.toSet().size, kinds.size)
    }

    @Test
    fun `a shelf's own well draws the known format's glyph when one resolved`() {
        assertEquals(
            coverlessWellIcon(PublicationFormat.CBZ).name,
            coverlessShelfIcon(PublicationFormat.CBZ).name,
        )
    }

    @Test
    fun `a shelf's own well falls back to a generic glyph when none resolved`() {
        val generic = coverlessShelfIcon(null).name
        assertNotEquals(generic, coverlessWellIcon(PublicationFormat.CBZ).name)
        assertNotEquals(generic, coverlessWellIcon(PublicationFormat.M4B).name)
    }

    // MARK: - The reach

    private val android: File by lazy {
        System.getProperty(ROOT_DIRECTORY)?.let(::File)
            ?: error(
                "$ROOT_DIRECTORY is unset. This test reads sibling modules' own sources and" +
                    " will not go looking for them elsewhere — run it through Gradle" +
                    " (`pnpm gradle :core:designsystem:testDebugUnitTest`), which sets the" +
                    " property from the Android root directory.",
            )
    }

    private fun sourceOf(path: String): String {
        val file = File(android, path)
        if (!file.isFile) error("$path is not under ${android.absolutePath} — has it moved?")
        return file.readText()
    }

    /**
     * Every surface that draws a publication's own well — the format overload, never the
     * shelf's `name` overload, which is the regression this guards: the two compile equally
     * well, so only a read of the call site tells them apart.
     */
    private val publicationSurfaces = listOf(
        "app/src/main/kotlin/app/storyarc/DownloadsParts.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/CoverGrid.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/DetailSeriesShelf.kt",
        "feature/library/src/main/kotlin/app/storyarc/feature/library/HomeCards.kt",
        "app/src/main/kotlin/app/storyarc/PlayerArtwork.kt",
    )

    @Test
    fun `every publication surface draws the format overload`() {
        for (path in publicationSurfaces) {
            val source = sourceOf(path)
            assertTrue(
                "$path does not call CoverlessWell(format = …). A publication's own well" +
                    " names its format rather than repeating a title the surface around it" +
                    " already states.",
                source.contains("CoverlessWell(format = "),
            )
            assertTrue(
                "$path still passes a title into CoverlessWell — the defect this guards.",
                !source.contains("CoverlessWell(title"),
            )
        }
    }

    /** The one shelf-level caller: named for the shelf, never for a format. */
    @Test
    fun `the shelf well draws the name overload`() {
        val source = sourceOf(
            "feature/library/src/main/kotlin/app/storyarc/feature/library/ShelfCover.kt",
        )
        assertTrue(
            "ShelfCover.kt does not call CoverlessWell(name = …, format = …).",
            source.contains("CoverlessWell(name = name, format = "),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from Gradle's own `rootDir`. */
        const val ROOT_DIRECTORY = "storyarc.android.rootDir"
    }
}
