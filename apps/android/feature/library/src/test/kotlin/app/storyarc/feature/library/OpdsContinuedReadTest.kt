package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * A catalogue's continuation: [OpdsContributor.page] asked a second time, for the link the
 * first page named rather than the catalogue's own root.
 *
 * A live local server, like `ServerLibraryOpdsCoverTest`'s own: the one thing under test is
 * which URL a second request reaches, and only a real two-page feed proves it rather than a
 * `next` field asserted in isolation.
 */
class OpdsContinuedReadTest {

    private lateinit var server: HttpServer
    private val base: String get() = "http://localhost:${server.address.port}/opds/"

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/opds/page1") { respond(it, feed(entry = "Tidal Reach", next = "page2")) }
        server.createContext("/opds/page2") { respond(it, feed(entry = "Second Wave", next = null)) }
        server.start()
    }

    @After
    fun stop() = server.stop(0)

    private fun respond(exchange: HttpExchange, body: String) {
        exchange.responseHeaders.add("Content-Type", "application/atom+xml")
        val bytes = body.toByteArray()
        exchange.sendResponseHeaders(200, bytes.size.toLong())
        exchange.responseBody.use { it.write(bytes) }
    }

    private fun feed(entry: String, next: String?) = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Library</title>
      ${next?.let { "<link rel=\"next\" href=\"$it\" type=\"application/atom+xml\"/>" }.orEmpty()}
      <entry>
        <title>$entry</title>
        <id>urn:uuid:$entry</id>
        <link rel="http://opds-spec.org/acquisition" href="download.cbz"
              type="application/vnd.comicbook+zip"/>
      </entry>
    </feed>
    """.trimIndent()

    @Test
    fun `a continuation asks for the next link, not the catalogue's root again`() = runBlocking {
        val source = UUID.randomUUID()
        val page = CataloguePage(title = "Library", url = "${base}page1", credential = null)

        val first = OpdsContributor.page(source, page, CertificatePins(), url = page.url)
        assertEquals(listOf("Tidal Reach"), first.slice.publications.map { it.displayTitle })
        assertTrue("a feed with a next link holds more", first.slice.holdsMore)
        assertEquals("${base}page2", first.next)

        // The bug this fixes: a continuation that always re-read `page.url` would land back
        // on page one here instead. Mutate the call below to `url = page.url` and this fails,
        // because the second page would then answer "Tidal Reach" again, not "Second Wave".
        val second = OpdsContributor.page(source, page, CertificatePins(), url = first.next!!)
        assertEquals(listOf("Second Wave"), second.slice.publications.map { it.displayTitle })
        assertFalse("the last page reports nothing more to read", second.slice.holdsMore)
        assertNull(second.next)
    }
}
