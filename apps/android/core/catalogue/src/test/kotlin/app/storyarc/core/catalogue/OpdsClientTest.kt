package app.storyarc.core.catalogue

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The client, against a real HTTP server on the loopback interface.
 *
 * A live server rather than a mocked connection: the behaviour under test is what the app
 * does with a 401, a 404 and a redirect, and those are decisions `HttpURLConnection` makes
 * as much as this code does. The JVM ships the server, so there is no dependency to add.
 *
 * iOS's `OpdsClientTests` covers the same cases through a `URLProtocol` stub.
 */
class OpdsClientTest {

    private lateinit var server: HttpServer
    private var status = 200
    private var body = ATOM
    private var headers = mapOf("Content-Type" to "application/atom+xml")
    private var seenAuthorization: String? = null

    private val base: String get() = "http://localhost:${server.address.port}/opds/"

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            seenAuthorization = exchange.requestHeaders.getFirst("Authorization")
            headers.forEach { (name, value) -> exchange.responseHeaders.add(name, value) }
            val bytes = body.toByteArray()
            exchange.sendResponseHeaders(status, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
    }

    @After
    fun stop() {
        server.stop(0)
    }

    @Test
    fun aFeedIsFetchedAndParsed() = runBlocking {
        val feed = OpdsClient().feed(base)
        assertEquals("Stubbed Library", feed.title)
        assertEquals("${base}unread", feed.navigation.first().href)
    }

    @Test
    fun aCredentialBecomesAnAuthorizationHeader() = runBlocking {
        OpdsClient().feed(base, OpdsCredential.Basic("ada", "lovelace"))
        // base64("ada:lovelace")
        assertEquals("Basic YWRhOmxvdmVsYWNl", seenAuthorization)
    }

    @Test
    fun aBearerTokenIsSentAsOne() = runBlocking {
        OpdsClient().feed(base, OpdsCredential.Bearer("abc123"))
        assertEquals("Bearer abc123", seenAuthorization)
    }

    @Test
    fun aChallengeSaysWhichSchemeToAskFor() = runBlocking {
        status = 401
        headers = mapOf("WWW-Authenticate" to """Basic realm="opds"""")
        body = ""
        val error = runCatching { OpdsClient().feed(base) }.exceptionOrNull()
        assertEquals(OpdsError.Unauthorized(OpdsError.AuthenticationScheme.BASIC), error)
    }

    @Test
    fun aChallengeWithNoSchemeStillSaysUnauthorized() = runBlocking {
        status = 401
        headers = emptyMap()
        body = ""
        val error = runCatching { OpdsClient().feed(base) }.exceptionOrNull()
        assertEquals(OpdsError.Unauthorized(null), error)
    }

    @Test
    fun anHttpFailureCarriesItsStatus() = runBlocking {
        status = 404
        body = ""
        val error = runCatching { OpdsClient().feed(base) }.exceptionOrNull()
        assertEquals(OpdsError.Http(404), error)
    }

    @Test
    fun anHtmlBodyIsNamedRatherThanParsedAsAFeed() = runBlocking {
        headers = mapOf("Content-Type" to "text/html")
        body = "<!DOCTYPE html><html><body>Sign in</body></html>"
        val error = runCatching { OpdsClient().feed(base) }.exceptionOrNull()
        assertEquals(OpdsError.NotAFeed(OpdsError.Received.Html), error)
    }

    @Test
    fun relativeLinksResolveAgainstWhereTheResponseCameFrom() = runBlocking {
        // A redirect moves what a relative href is relative to. Resolving against the
        // request would point every link on the page at the old path.
        server.createContext("/moved") { exchange ->
            exchange.responseHeaders.add("Location", "/catalogue/")
            exchange.sendResponseHeaders(302, -1)
            exchange.close()
        }
        server.createContext("/catalogue/") { exchange ->
            val bytes = ATOM.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/atom+xml")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        val feed = OpdsClient().feed("http://localhost:${server.address.port}/moved")
        assertEquals(
            "http://localhost:${server.address.port}/catalogue/unread",
            feed.navigation.first().href,
        )
    }

    @Test
    fun aFileIsFetchedAsBytes() = runBlocking {
        headers = emptyMap()
        body = "abc"
        assertTrue("abc".toByteArray().contentEquals(OpdsClient().bytes("${base}1.epub")))
    }

    private companion object {
        val ATOM = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Stubbed Library</title>
          <link rel="subsection" href="unread" title="Unread"
                type="application/atom+xml;profile=opds-catalog"/>
        </feed>
        """.trimIndent()
    }
}
