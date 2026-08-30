package app.storyarc.core.catalogue

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The document an OPDS 1.2 catalogue advertises its search through.
 *
 * `opds-catalog`: "when a catalogue advertises an OpenSearch description, searching within
 * that source queries the server rather than filtering locally". A 2.0 feed carries the
 * template in the link's own href; a 1.2 feed points at one of these, which is the commoner
 * of the two shapes and the one nothing followed until now — every such catalogue fell back
 * to filtering what was already loaded.
 *
 * The same fixtures iOS's `OpenSearchTests` uses, in the same order, so a difference between
 * the platforms is a failing test rather than a surprise on one device.
 */
class OpenSearchTest {

    private val document = "https://library.example/opds/opensearch.xml"

    private fun template(xml: String): String? =
        OpenSearchDescription.template(xml.toByteArray(), document)

    @Test
    fun `an absolute template is taken as written`() {
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <ShortName>Library</ShortName>
              <Url type="application/atom+xml;profile=opds-catalog"
                   template="https://library.example/search?q={searchTerms}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertEquals("https://library.example/search?q={searchTerms}", found)
    }

    @Test
    fun `a relative template is resolved against the document`() {
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="application/atom+xml" template="../search?q={searchTerms}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertEquals("https://library.example/search?q={searchTerms}", found)
    }

    @Test
    fun `the placeholder survives resolution`() {
        // Percent-encoding the braces would leave a template nothing can substitute into,
        // and `fill` would then refuse it as a search that matched everything.
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="application/atom+xml" template="search?q={searchTerms}&amp;page={startPage?}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertTrue(found?.contains("{searchTerms}") == true)
    }

    @Test
    fun `the opds profile wins over a page`() {
        // Calibre-Web's own document lists the HTML search first.
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="text/html" template="https://library.example/ui?q={searchTerms}"/>
              <Url type="application/atom+xml;profile=opds-catalog"
                   template="https://library.example/opds/search?q={searchTerms}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertEquals("https://library.example/opds/search?q={searchTerms}", found)
    }

    @Test
    fun `atom wins when no profile is declared`() {
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="text/html" template="https://library.example/ui?q={searchTerms}"/>
              <Url type="application/atom+xml" template="https://library.example/feed?q={searchTerms}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertEquals("https://library.example/feed?q={searchTerms}", found)
    }

    @Test
    fun `a document offering only a page offers nothing`() {
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="text/html" template="https://library.example/ui?q={searchTerms}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertNull(found)
    }

    @Test
    fun `a Url without a template is skipped`() {
        val found = template(
            """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="application/atom+xml"/>
              <Url type="application/atom+xml" template="https://library.example/s?q={searchTerms}"/>
            </OpenSearchDescription>
            """.trimIndent(),
        )
        assertEquals("https://library.example/s?q={searchTerms}", found)
    }

    @Test
    fun `something that is not a description document offers nothing`() {
        assertNull(template("<html><body>Sign in</body></html>"))
    }
}
