package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where a catalogue search goes, and what it keeps when it cannot go anywhere.
 *
 * `opds-catalog`: "searching within that source queries the server rather than filtering
 * locally", and "a catalogue without search falls back to filtering the cached catalogue,
 * and says so". Two decisions: which address a term becomes, and which entries a term keeps.
 * Neither had a test on either platform, and this half of the feature had no screen at all —
 * `CatalogueBrowser.search` was written, translated into four languages, and called by
 * nothing.
 *
 * The [CatalogueBrowser] itself is not built here: it is an Android `ViewModel` holding a
 * `Context`, which a JVM unit test cannot construct — the same limit `SourceRemovalTest`
 * records. What is asserted is the pair of pure decisions underneath it.
 *
 * iOS's `CatalogueSearchTests` asserts these cases in this order.
 */
class CatalogueSearchTest {

    // Where a term goes.

    @Test
    fun `an OpenSearch template takes the term`() {
        assertEquals(
            "https://books.example/search?q=bone",
            CatalogueBrowser.fill("https://books.example/search?q={searchTerms}", "bone"),
        )
    }

    @Test
    fun `the four spellings an OPDS 2 template uses are all substituted`() {
        for (placeholder in listOf("{query}", "{?query}", "{q}", "{?q}")) {
            assertEquals(
                "https://books.example/s?t=bone",
                CatalogueBrowser.fill("https://books.example/s?t=$placeholder", "bone"),
            )
        }
    }

    @Test
    fun `a space becomes percent-twenty, not a plus`() {
        assertEquals(
            "https://books.example/s?q=sandman%20ouverture",
            CatalogueBrowser.fill("https://books.example/s?q={searchTerms}", "sandman ouverture"),
        )
    }

    @Test
    fun `a term outside ASCII is escaped by its bytes`() {
        assertEquals(
            "https://books.example/s?q=%C3%A9p%C3%A9e",
            CatalogueBrowser.fill("https://books.example/s?q={searchTerms}", "épée"),
        )
    }

    @Test
    fun `the unreserved marks stand as written`() {
        assertEquals(
            "https://books.example/s?q=a-b_c.d*e",
            CatalogueBrowser.fill("https://books.example/s?q={searchTerms}", "a-b_c.d*e"),
        )
    }

    @Test
    fun `a template with no placeholder is not a search`() {
        // Substituting nothing would fetch the unfiltered feed and look like a search that
        // matched everything.
        assertNull(CatalogueBrowser.fill("https://books.example/all", "bone"))
    }

    // What a term keeps.

    private fun entry(
        title: String = "Bone",
        authors: List<String> = listOf("Jeff Smith"),
        series: String? = "Bone",
    ) = OpdsEntry(id = "1", title = title, authors = authors, series = series)

    @Test
    fun `a title matches whatever case it was typed in`() {
        assertTrue(entry(title = "The Sandman", authors = emptyList(), series = null).matches("sandMAN"))
    }

    @Test
    fun `an author matches`() {
        assertTrue(
            entry(title = "Out From Boneville", authors = listOf("Jeff Smith"), series = null)
                .matches("smith"),
        )
    }

    @Test
    fun `a series matches`() {
        assertTrue(entry(title = "Volume One", authors = emptyList(), series = "Berserk").matches("berserk"))
    }

    @Test
    fun `an entry the term is nowhere in does not match`() {
        assertFalse(entry(title = "Bone", authors = listOf("Jeff Smith"), series = "Bone").matches("akira"))
    }
}
