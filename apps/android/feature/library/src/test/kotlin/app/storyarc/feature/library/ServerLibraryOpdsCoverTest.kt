package app.storyarc.feature.library

import android.graphics.Bitmap
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * An OPDS row's artwork, fetched through the catalogue it came from. 11.7 / D29:
 * `OpdsContributor` keeps no acquisition address — such a link can carry a key in its
 * query — so the only way to its cover is to find the entry again by the id the row was
 * filed under.
 *
 * A live local server, like `OpdsClientTest`'s own: the behaviour under test is what
 * [ServerLibrary.cover] does with a real feed and a real image, and `HttpURLConnection`
 * makes those decisions as much as this code does.
 *
 * `GraphicsMode.NATIVE` for the reason `ServerCoverCacheTest` gives: Robolectric's legacy
 * graphics measure a decoded bitmap as a fixed placeholder, which would make a real decode
 * indistinguishable from nothing decoded at all.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ServerLibraryOpdsCoverTest {

    private lateinit var server: HttpServer
    private var thumbnailRequested = false

    private val base: String get() = "http://localhost:${server.address.port}/opds/"

    private fun onePixelPng(): ByteArray {
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.MAGENTA)
        val out = java.io.ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.start()
    }

    @After
    fun stop() {
        server.stop(0)
    }

    /**
     * A feed of two entries, so a cover fetched for [entryId] is proof the entry was found
     * by its own id — a feed of one would answer the same way whichever entry a bug
     * happened to pick.
     */
    private fun serveFeed(entryId: String) {
        server.createContext("/opds/") { exchange ->
            val atom = """
            <?xml version="1.0"?>
            <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
            <entry><title>Some Other Book</title><id>urn:uuid:other</id>
            <link rel="http://opds-spec.org/image/thumbnail" href="thumb/other.jpg" type="image/png"/>
            <link rel="http://opds-spec.org/acquisition" href="download/other.epub"
                  type="application/epub+zip"/>
            </entry>
            <entry><title>Tidal Reach</title><id>$entryId</id>
            <link rel="http://opds-spec.org/image/thumbnail" href="thumb/1.jpg" type="image/png"/>
            <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
                  type="application/epub+zip"/>
            </entry></feed>
            """.trimIndent()
            val bytes = atom.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/atom+xml")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.createContext("/opds/thumb/1.jpg") { exchange ->
            thumbnailRequested = true
            val bytes = onePixelPng()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.createContext("/opds/thumb/other.jpg") { exchange ->
            exchange.sendResponseHeaders(404, -1)
            exchange.close()
        }
    }

    @Test
    fun `a row's cover is fetched by finding its entry again, through the source it came from`() = runBlocking {
        val entryId = "urn:uuid:${UUID.randomUUID()}"
        serveFeed(entryId)

        val sourceId = UUID.randomUUID()
        val source = Source(id = sourceId, displayName = "Library", kind = SourceKind.OPDS_CATALOG, locator = base)
        val publication = Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId, "opds:$entryId"),
            ),
            format = PublicationFormat.EPUB,
            displayTitle = "Tidal Reach",
            origin = MetadataOrigin.AUTHORITATIVE,
        )

        val cover = ServerLibrary.cover(publication, listOf(source), credentials = null, pins = CertificatePins())

        assertNotNull(cover)
        assertEquals(true, thumbnailRequested)
    }

    @Test
    fun `the full cover stands in when the entry offers no thumbnail`() = runBlocking {
        val entryId = "urn:uuid:${UUID.randomUUID()}"
        server.createContext("/opds/") { exchange ->
            val atom = """
            <?xml version="1.0"?>
            <feed xmlns="http://www.w3.org/2005/Atom"><title>t</title>
            <entry><title>e</title><id>$entryId</id>
            <link rel="http://opds-spec.org/image" href="cover/1.jpg" type="image/png"/>
            <link rel="http://opds-spec.org/acquisition" href="download/1.epub"
                  type="application/epub+zip"/>
            </entry></feed>
            """.trimIndent()
            val bytes = atom.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/atom+xml")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        var coverRequested = false
        server.createContext("/opds/cover/1.jpg") { exchange ->
            coverRequested = true
            val bytes = onePixelPng()
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }

        val sourceId = UUID.randomUUID()
        val source = Source(id = sourceId, displayName = "Library", kind = SourceKind.OPDS_CATALOG, locator = base)
        val publication = Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId, "opds:$entryId"),
            ),
            format = PublicationFormat.EPUB,
            displayTitle = "e",
            origin = MetadataOrigin.AUTHORITATIVE,
        )

        val cover = ServerLibrary.cover(publication, listOf(source), credentials = null, pins = CertificatePins())

        assertNotNull(cover)
        assertEquals(true, coverRequested)
    }

    @Test
    fun `a source removed since the row was filed draws nothing, not a crash`() = runBlocking {
        // Another, unrelated OPDS source answers through the same server with a real feed
        // and a real cover for the very id this row carries -- the point is that this
        // row's own sourceId is matched to its own source, not merely that the list of
        // sources holds something reachable that happens to answer.
        serveFeed("urn:uuid:1")
        val publication = Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(UUID.randomUUID(), "opds:urn:uuid:1"),
            ),
            format = PublicationFormat.EPUB,
            displayTitle = "Gone",
            origin = MetadataOrigin.AUTHORITATIVE,
        )
        val unrelated = Source(displayName = "Some Other Library", kind = SourceKind.OPDS_CATALOG, locator = base)

        val cover = ServerLibrary.cover(publication, listOf(unrelated), credentials = null, pins = CertificatePins())

        assertNull(cover)
    }

    @Test
    fun `a row whose remote id carries no opds prefix is never read as one`() = runBlocking {
        // An OPDS source given a non-"opds:" id isolates this guard from the kind check
        // CataloguePage.of already applies on its own.
        val entryId = "urn:uuid:${UUID.randomUUID()}"
        serveFeed(entryId)

        val sourceId = UUID.randomUUID()
        val source = Source(id = sourceId, displayName = "Library", kind = SourceKind.OPDS_CATALOG, locator = base)
        val publication = Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId, "chapter:1"),
            ),
            format = PublicationFormat.CBZ,
            displayTitle = "A Chapter",
            origin = MetadataOrigin.AUTHORITATIVE,
        )

        val cover = ServerLibrary.cover(publication, listOf(source), credentials = null, pins = CertificatePins())

        assertNull(cover)
        assertEquals(false, thumbnailRequested)
    }

    @Test
    fun `a publication with no server identity at all is never asked for one`() = runBlocking {
        val publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/a/b.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "Local",
            origin = MetadataOrigin.INFERRED,
        )

        val cover = ServerLibrary.cover(publication, sources = emptyList(), credentials = null, pins = CertificatePins())

        assertNull(cover)
    }
}
