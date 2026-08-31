package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What the second line under a cover is allowed to say.
 *
 * `library-browsing` wants the caption to distinguish a publication from its neighbours,
 * and a line that repeats the title distinguishes nothing — it reads as a rendering fault.
 * The shelf did exactly that on every numbered series: the condition compared the *bare*
 * series against the title while the string it returned was the *composed*
 * `"<series> #<number>"`, so `Harbour Lights` + `1` under the title `Harbour Lights #1`
 * sailed through and the cover said `Harbour Lights #1` twice.
 *
 * iOS's `SeriesLineTests` asserts the same cases against the same function.
 */
class SeriesLineTest {

    private fun publication(
        title: String,
        series: String? = null,
        number: String? = null,
        authors: List<String> = emptyList(),
    ) = Publication(
        identity = PublicationIdentity(contentDigest = title),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        number = number,
        authors = authors,
        origin = MetadataOrigin.EMBEDDED,
    )

    @Test
    fun `a composed line identical to the title is not shown`() {
        assertNull(seriesLine(publication("Harbour Lights #1", "Harbour Lights", "1")))
    }

    @Test
    fun `a composed line that adds the number is shown`() {
        // The title is the series alone, so the number is a fact the title does not carry.
        assertEquals(
            "Harbour Lights #1",
            seriesLine(publication("Harbour Lights", "Harbour Lights", "1")),
        )
    }

    @Test
    fun `a series that is not the title is shown, numbered or not`() {
        assertEquals("Harbour Lights", seriesLine(publication("Low Tide", "Harbour Lights")))
        assertEquals(
            "Harbour Lights #3",
            seriesLine(publication("Low Tide", "Harbour Lights", "3")),
        )
    }

    @Test
    fun `a bare series equal to the title is not shown`() {
        assertNull(seriesLine(publication("Harbour Lights", "Harbour Lights")))
    }

    @Test
    fun `case is not a second fact`() {
        // A title inferred from a filename is often the series and the number joined back
        // together, and `HARBOUR LIGHTS #1` over `Harbour Lights #1` is the same words.
        assertNull(seriesLine(publication("HARBOUR LIGHTS #1", "Harbour Lights", "1")))
    }

    @Test
    fun `a publication with no series has no line`() {
        assertNull(seriesLine(publication("Glasshouse")))
    }

    /**
     * The other half of the fix: what the cover says *instead*. A caption that fell back to
     * nothing would trade a repeated line for a missing one. `cellSubtitle` is `@Composable`
     * and this module has no Compose test rule, so the fall-through is asserted here in the
     * shape the caption uses it.
     */
    @Test
    fun `the cover falls through to the author when the series line is refused`() {
        val repeated = publication("Harbour Lights #1", "Harbour Lights", "1", listOf("Ada"))
        val distinct = publication("Low Tide", "Harbour Lights", "3", listOf("Ada"))

        assertEquals("Ada", seriesLine(repeated) ?: repeated.authors.firstOrNull())
        assertEquals("Harbour Lights #3", seriesLine(distinct) ?: distinct.authors.firstOrNull())
    }
}
