package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * A series line says something the title does not, or it is not drawn.
 *
 * **Photographed on 2026-09-05**: the publication page for `Broken Transfer.cbz` read
 * `Broken Transfer` in the app bar and `Broken Transfer` again immediately beneath it. A title
 * inferred from a filename is usually the series and the number joined back together, so a
 * standalone publication carries a series equal to its own title — and three surfaces drew both.
 *
 * The rule already existed for the grid and list captions and for iOS; what was missing was the
 * page, the catalogue entry and the search row using it. These cases pin the rule itself.
 */
class SeriesLineTest {

    @Test
    fun `a series that repeats the title is not drawn`() {
        assertNull(seriesLine(series = "Broken Transfer", title = "Broken Transfer"))
    }

    @Test
    fun `case alone is not a second fact about the publication`() {
        assertNull(seriesLine(series = "broken transfer", title = "Broken Transfer"))
    }

    @Test
    fun `a series that says something else is drawn`() {
        assertEquals("Harbour Lights", seriesLine(series = "Harbour Lights", title = "The Ridge Road"))
    }

    @Test
    fun `the number joins the series, and the pair is compared to the title`() {
        // The case that matters for a feed generated from filenames: the entry's title already
        // reads `Harbour Lights #1`, so the line built from its parts must not be drawn again.
        assertNull(seriesLine(series = "Harbour Lights", number = "1", title = "Harbour Lights #1"))
        assertEquals(
            "Harbour Lights #2",
            seriesLine(series = "Harbour Lights", number = "2", title = "Harbour Lights #1"),
        )
    }

    @Test
    fun `no series, or a blank one, draws nothing`() {
        assertNull(seriesLine(series = null, title = "Anything"))
        assertNull(seriesLine(series = "   ", title = "Anything"))
    }

    @Test
    fun `a blank number is not joined`() {
        assertEquals("Harbour Lights", seriesLine(series = "Harbour Lights", number = " ", title = "Other"))
    }
}
