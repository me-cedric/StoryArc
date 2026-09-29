package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * A streamed read carries a source's credential only to that source's own origin.
 *
 * dl-core 1.6: `HttpSource`'s default transport is unauthenticated, so a catalogue behind
 * Basic or Bearer answered 401 the moment a reader opened a book while it was still
 * arriving. iOS's `SourceRangeTransportTests` makes the same claims through a `URLProtocol`
 * stub; this is a real server on the loopback interface for the end-to-end fetch, the way
 * `OpdsClientTest` already covers `OpdsClient` itself, and a direct call for the origin
 * match that [SourceRangeTransport.credentialFor] gates on -- the platform Keystore behind
 * an actual credential only a device or an emulator can open.
 */
class SourceRangeTransportTest {

    private lateinit var server: HttpServer
    private var seenAuthorization: String? = null

    private val base: String get() = "http://localhost:${server.address.port}/book.epub"

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            seenAuthorization = exchange.requestHeaders.getFirst("Authorization")
            exchange.responseHeaders.add("Content-Range", "bytes 0-0/10")
            exchange.sendResponseHeaders(206, 1)
            exchange.responseBody.use { it.write(byteArrayOf(0)) }
        }
        server.start()
    }

    @After
    fun stop() {
        server.stop(0)
    }

    private fun source(locator: String) = Source(
        displayName = "Library",
        kind = SourceKind.OPDS_CATALOG,
        credentialReference = "ref",
        locator = locator,
    )

    @Test
    fun `an address with no configured source carries no credential`() = runBlocking {
        val transport = SourceRangeTransport(
            pins = CertificatePins(),
            credentials = null,
            sources = { emptyList() },
        )

        transport.fetch(base, from = 0, through = 0)

        assertNull(seenAuthorization)
    }

    @Test
    fun `a source configured at the address is the one eligible for its credential`() {
        val configured = source(locator = base.substringBeforeLast("/book.epub"))
        val transport = SourceRangeTransport(
            pins = CertificatePins(),
            credentials = null,
            sources = { listOf(configured) },
        )

        val origin = requireNotNull(OpdsOrigin.of(base))
        assertEquals(configured, transport.sourceEligibleFor(origin))
    }

    @Test
    fun `a source configured at a different address is not eligible`() {
        val elsewhere = source(locator = "http://elsewhere.invalid")
        val transport = SourceRangeTransport(
            pins = CertificatePins(),
            credentials = null,
            sources = { listOf(elsewhere) },
        )

        val origin = requireNotNull(OpdsOrigin.of(base))
        assertNull(transport.sourceEligibleFor(origin))
    }
}
