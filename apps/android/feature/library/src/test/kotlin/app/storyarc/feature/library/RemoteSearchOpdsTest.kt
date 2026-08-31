package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.SearchResult
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.net.URLDecoder
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * The photographed defect, reproduced against a real server and then fixed.
 *
 * On 2026-08-31 a reader searched *Fine Print* on a device with a catalogue and a local
 * folder configured. `scripts/opds-server.mjs` logged `200 GET /opds/all?q=Fine%20Print` —
 * so the catalogue was asked and answered — and not one of its results reached the screen.
 * The capture is `docs/designs/screenshots/after-2026-08-31/ios-search-remote-and-away-dark.png`.
 *
 * The two feeds below are the exact bytes that server sends, so the dialect under test is the
 * one the app was actually driven against rather than a hand-written idea of it. Everything
 * from the root feed to the finished list is exercised: the OpenSearch template is found in
 * the navigation feed, the term is substituted and escaped, a second request is made, the
 * acquisition feed is parsed, and the rows are merged with what the device already holds.
 *
 * A live server on the loopback interface rather than a mocked connection, following
 * `OpdsClientTest`: the JVM ships one, so there is no dependency to add. iOS's
 * `RemoteSearchOpdsTests` asserts the same outcome from the same bytes, through its own
 * parser — it has no equivalent seam for the fetch, which `OpdsClientTests` covers there.
 */
class RemoteSearchOpdsTest {

    private lateinit var server: HttpServer
    private var searchPathsSeen = mutableListOf<String>()

    private val root: String get() = "http://localhost:${server.address.port}/opds"

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/opds") { exchange ->
            val query = exchange.requestURI.rawQuery
            val term = query
                ?.split("&")
                ?.firstOrNull { it.startsWith("q=") }
                ?.let { URLDecoder.decode(it.removePrefix("q="), "UTF-8") }
            val body = if (exchange.requestURI.path == "/opds/all") {
                searchPathsSeen += exchange.requestURI.toString()
                acquisitionFeed(term)
            } else {
                NAVIGATION_FEED
            }.toByteArray()
            exchange.responseHeaders.add(
                "Content-Type",
                "application/atom+xml;profile=opds-catalog",
            )
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.start()
    }

    @After
    fun stop() {
        server.stop(0)
    }

    private val catalogue = Source(
        displayName = "StoryArc Test Catalogue",
        kind = SourceKind.OPDS_CATALOG,
    )

    private fun page() = CataloguePage(catalogue.displayName, root, credential = null)

    @Test
    fun `the catalogue is asked at the address its own feed advertises`() = runBlocking {
        RemoteSearch.entries("Fine Print", page(), CertificatePins())
        // The term is escaped the way both platforms escape it, so the two apps ask one
        // question rather than two spellings of it.
        assertEquals(listOf("/opds/all?q=Fine%20Print"), searchPathsSeen)
    }

    @Test
    fun `what the catalogue answers becomes a row that names the catalogue`() = runBlocking {
        val rows = RemoteSearch.catalogueRows(
            RemoteSearch.entries("Fine Print", page(), CertificatePins()),
            catalogue,
        )
        val found = FoundRow.away(rows, catalogue)
        assertEquals(listOf("Fine Print"), found.map { it.result.title })
        assertEquals(
            listOf(SearchOrigin.Library(catalogue.id.toString(), "StoryArc Test Catalogue")),
            found.map { it.origin },
        )
    }

    @Test
    fun `the catalogue's answer reaches the list beside the copy on the device`() = runBlocking {
        // The defect, as a case. Before this change both rows folded to one and the reader
        // was shown only what the device held, with nothing on screen to say a catalogue had
        // answered at all.
        val onDevice = FoundRow(
            SearchResult(
                kind = MatchKind.PUBLICATION,
                title = "Fine Print",
                publicationId = "held:fine-print",
            ),
            SearchOrigin.Library("folder", "Attic NAS"),
        )
        val listing = SearchListing
            .of(
                "Fine Print",
                namesOrigin = true,
                local = listOf(onDevice),
                asking = listOf(catalogue.id.toString()),
            )
            .answered(
                catalogue.id.toString(),
                FoundRow.away(
                    RemoteSearch.catalogueRows(
                        RemoteSearch.entries("Fine Print", page(), CertificatePins()),
                        catalogue,
                    ),
                    catalogue,
                ),
            )

        assertEquals(listOf("Fine Print", "Fine Print"), listing.rows.map { it.result.title })
        assertEquals(
            listOf("Attic NAS", "StoryArc Test Catalogue"),
            listing.rows.map { (it.origin as SearchOrigin.Library).name },
        )
        assertEquals(listOf(MatchKind.PUBLICATION), listing.groups.map { it.kind })
    }

    @Test
    fun `a term the catalogue matches nothing for is an empty answer and not a failure`() =
        runBlocking {
            val rows = RemoteSearch.entries("Nothing At All", page(), CertificatePins())
            assertEquals(emptyList<String>(), rows.map { it.title })
        }

    private companion object {

        /**
         * `scripts/opds-server.mjs`'s `/opds`, verbatim but for the identifier, which carries
         * a port this test cannot know in advance. The `rel="search"` link is what makes the
         * whole path work: an inline OpenSearch template with a `{searchTerms}` placeholder.
         */
        const val NAVIGATION_FEED = """<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <id>urn:storyarc:catalogue</id>
  <title>StoryArc Test Catalogue</title>
  <updated>1970-01-01T00:00:00Z</updated>
  <link rel="self" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <link rel="start" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <link rel="search" href="/opds/all?q={searchTerms}" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <link rel="subsection" href="/opds/all" title="All publications"
        thr:count="15" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
</feed>
"""

        /** `scripts/opds-server.mjs`'s `/opds/all`, filtered by the term the way it filters. */
        fun acquisitionFeed(term: String?): String {
            val matches = term == null || "fine print".contains(term.lowercase())
            val entry = if (matches) {
                """  <entry>
    <id>urn:storyarc:4</id>
    <title>Fine Print</title>
    <updated>2026-08-30T11:52:01Z</updated>
    <author><name>Ada Lovelace</name></author>
    <summary>A test publication, application/vnd.comicbook+zip.</summary>
    <link rel="http://opds-spec.org/image" href="/covers/Fine%20Print.cbz" type="image/png"/>
    <link rel="http://opds-spec.org/acquisition"
          href="/files/Fine%20Print.cbz" type="application/vnd.comicbook+zip"/>
  </entry>
"""
            } else {
                ""
            }
            return """<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:opds="http://opds-spec.org/2010/catalog"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <id>urn:storyarc:All publications</id>
  <title>All publications</title>
  <link rel="self" href="/opds/all" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <link rel="up" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
$entry</feed>
"""
        }
    }
}
