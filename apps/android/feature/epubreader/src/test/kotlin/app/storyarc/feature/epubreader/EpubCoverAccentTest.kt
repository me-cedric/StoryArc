package app.storyarc.feature.epubreader

import androidx.compose.ui.graphics.Color
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.ReadingContrast
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The end of an EPUB takes the cover's accent, as the comic reader's end screen does. D21,
 * task 9.7. iOS's `EpubCoverAccentTests` asserts the same three things.
 *
 * Robolectric with native graphics, because the cover is a PNG Readium decodes into a real
 * `Bitmap`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class EpubCoverAccentTest {

    private fun colours(book: String): CoverColours? = runBlocking {
        val path = File(
            System.getProperty("storyarc.epubreader.projectDir"),
            "../../../../packages/test-fixtures/ebooks/$book",
        ).canonicalPath
        val opening = openEpub(RuntimeEnvironment.getApplication(), path)
        val publication = (opening as? EpubOpening.Opened)?.publication ?: error("$book did not open: $opening")
        epubCoverColours(publication)
    }

    @Test
    fun `a book with a coloured cover gives its end of book that cover's accent`() {
        // `fixture.epub` declares a cover image, a solid #255B97 blue.
        val colours = colours("fixture.epub") ?: error("the coloured cover gave no colours")

        assertNotEquals(colours.wash, colours.accent)
        val button = endButtonColours(colours, brand = Color.Magenta)
        assertNotEquals(Color.Magenta, button.fill)
    }

    @Test
    fun `the label on the accent clears the 3 to 1 floor, and so does the accent on its wash`() {
        val colours = colours("fixture.epub")!!

        assertTrue(ReadingContrast.ratio(colours.onAccent, colours.accent) >= 3.0)
        assertTrue(ReadingContrast.ratio(colours.accent, colours.wash) >= 3.0)
    }

    @Test
    fun `a book with no cover keeps the brand accent, with white on it`() {
        // `series.epub` declares no cover at all.
        assertNull(colours("series.epub"))

        val button = endButtonColours(null, brand = Color.Magenta)
        assertEquals(EndButtonColours(Color.Magenta, Color.White), button)
    }
}
