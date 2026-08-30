package app.storyarc.core.format

import app.storyarc.core.model.SearchSnippet
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Mirrors iOS's `PdfTextSearchTests`, assertion for assertion.
 *
 * Pure text, no PDF: what a page's text layer says is the platform's business, and what is done
 * with the string it hands over is this app's. Keeping the two apart is what lets the snippet
 * rule be asserted identically on both sides.
 */
class PdfTextSearchTest {

    private val page = "Chapter One\nThe sandman walked."

    @Test
    fun `a hit is reported with its page and its offsets`() {
        val found = PdfTextSearch.matches(page, page = 4, query = "sandman")
        assertEquals(1, found.size)
        assertEquals(PdfLocator(page = 4, start = 16, end = 23), found.first().locator)
    }

    @Test
    fun `every occurrence on a page is reported, in reading order`() {
        val found = PdfTextSearch.matches("one two one", page = 0, query = "one")
        assertEquals(listOf(0, 8), found.map { it.locator.start })
    }

    @Test
    fun `the search is case-insensitive, because a search box is not a grep`() {
        assertEquals(1, PdfTextSearch.matches(page, page = 0, query = "SANDMAN").size)
    }

    @Test
    fun `a word that is not on the page yields nothing`() {
        assertTrue(PdfTextSearch.matches(page, page = 0, query = "dreaming").isEmpty())
    }

    @Test
    fun `an empty query yields nothing rather than every position`() {
        assertTrue(PdfTextSearch.matches(page, page = 0, query = "").isEmpty())
    }

    @Test
    fun `the limit caps the run`() {
        assertEquals(1, PdfTextSearch.matches("aaaa", page = 0, query = "aa", limit = 1).size)
    }

    @Test
    fun `overlapping runs are reported once each, not once per position`() {
        val found = PdfTextSearch.matches("aaaa", page = 0, query = "aa")
        assertEquals(listOf(0, 2), found.map { it.locator.start })
    }

    @Test
    fun `the snippet carries the words around the hit`() {
        val snippet = PdfTextSearch.matches(page, page = 0, query = "sandman").first().snippet
        assertEquals("Chapter One The", snippet.before)
        assertEquals("sandman", snippet.match)
        assertEquals("walked.", snippet.after)
    }

    @Test
    fun `a page's own line breaks do not reach the row`() {
        val line = PdfTextSearch.matches(page, page = 0, query = "sandman").first().snippet.line
        assertEquals("Chapter One The sandman walked.", line)
    }

    @Test
    fun `context is trimmed by the one snippet rule, not by a second one`() {
        val long = "word ".repeat(60)
        val snippet = PdfTextSearch
            .matches(long + "sandman " + long, page = 0, query = "sandman")
            .first().snippet
        // The budget, split between two sides that both had more to give.
        assertTrue(snippet.before.length <= SearchSnippet.BUDGET / 2)
        assertTrue(snippet.after.length <= SearchSnippet.BUDGET / 2)
    }

    @Test
    fun `the offsets point into the untouched text, so the words read back`() {
        val hit = PdfTextSearch.matches(page, page = 0, query = "sandman").first()
        assertEquals("sandman", PdfTextSearch.text(hit.locator, page))
    }

    @Test
    fun `a locator that names nothing in the text reads back as nothing`() {
        assertNull(PdfTextSearch.text(PdfLocator(page = 0, start = 900, end = 950), page))
        assertNull(PdfTextSearch.text(PdfLocator(page = 0, start = 4, end = 4), page))
    }
}
