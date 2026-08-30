package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Mirrors iOS's `PdfLocatorTests`, assertion for assertion. */
class PdfLocatorTest {

    @Test
    fun `the written form is one exact string, so both platforms write the same record`() {
        val locator = PdfLocator(page = 11, start = 340, end = 392)
        assertEquals("""{"page":11,"start":340,"end":392}""", locator.json)
    }

    @Test
    fun `a locator round-trips through its own JSON`() {
        val locator = PdfLocator(page = 0, start = 0, end = 7)
        assertEquals(locator, PdfLocator.of(locator.json))
    }

    @Test
    fun `a string that is not a locator reads as nothing rather than as zeros`() {
        assertNull(PdfLocator.of(""))
        assertNull(PdfLocator.of("not json at all"))
        // A reflowable locator, which is what the same field holds for an EPUB.
        assertNull(PdfLocator.of("""{"href":"chapter1.xhtml","type":"text/html"}"""))
    }

    @Test
    fun `a run that ends before it starts is refused`() {
        assertNull(PdfLocator.of("""{"page":1,"start":40,"end":10}"""))
    }

    @Test
    fun `a page before the first one is refused`() {
        assertNull(PdfLocator.of("""{"page":-1,"start":0,"end":10}"""))
    }

    @Test
    fun `an empty run is read, because a caret is a position a reader can be at`() {
        assertEquals(
            PdfLocator(page = 2, start = 5, end = 5),
            PdfLocator.of("""{"page":2,"start":5,"end":5}"""),
        )
    }
}
