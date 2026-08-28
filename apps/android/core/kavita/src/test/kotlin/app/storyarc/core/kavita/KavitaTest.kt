package app.storyarc.core.kavita

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The same claims iOS's `KavitaAddressTests` makes. */
class KavitaAddressTest {

    @Test
    fun aPastedOpdsUrlYieldsTheBaseAndTheKey() {
        val address = KavitaAddress.fromOpds("https://kavita.example/api/opds/abc123def")!!
        assertEquals("https://kavita.example", address.base)
        assertEquals("abc123def", address.apiKey)
    }

    @Test
    fun aServerBehindAReverseProxySubpathKeepsItsPrefix() {
        // Dropping the prefix would send every later request to a path the proxy does not
        // serve.
        val address = KavitaAddress.fromOpds("https://home.example/books/api/opds/key")!!
        assertEquals("https://home.example/books", address.base)
    }

    @Test
    fun aPortSurvives() {
        val address = KavitaAddress.fromOpds("http://192.168.1.10:5000/api/opds/key")!!
        assertEquals("http://192.168.1.10:5000", address.base)
    }

    @Test
    fun somethingThatIsNotAKavitaOpdsUrlIsRefused() {
        assertNull(KavitaAddress.fromOpds("https://kavita.example/api/opds"))
        assertNull(KavitaAddress.fromOpds("https://calibre.example/opds"))
        assertNull(KavitaAddress.fromOpds("https://kavita.example/"))
        assertNull(KavitaAddress.fromOpds(""))
    }

    @Test
    fun aTypedBaseIsTidiedRatherThanRefused() {
        for (typed in listOf(
            "https://kavita.example",
            "https://kavita.example/",
            "https://kavita.example/api",
            "https://kavita.example/api/",
            "kavita.example",
        )) {
            assertEquals(typed, "https://kavita.example", KavitaAddress.from(typed, "k")!!.base)
        }
    }

    @Test
    fun aMissingKeyOrHostIsRefused() {
        assertNull(KavitaAddress.from("https://kavita.example", "  "))
        assertNull(KavitaAddress.from("  ", "k"))
    }

    @Test
    fun anEndpointHangsOffTheBaseUnderApi() {
        val address = KavitaAddress.from("https://k.example/books", "k")!!
        assertEquals("https://k.example/books/api/Library/libraries", address.endpoint("Library/libraries"))
    }

    @Test
    fun aVersionIsComparedAsAVersion() {
        assertTrue(KavitaVersion.of("0.7.14")!! < KavitaVersion.of("0.8.0")!!)
        // A build number is ignored rather than refused.
        assertEquals(KavitaVersion(0, 8, 3), KavitaVersion.of("0.8.3.2"))
        assertNull(KavitaVersion.of("nonsense"))
    }
}

/**
 * The connection and library requirements, against a real server on the loopback interface.
 *
 * A live server rather than a mocked connection, for the reason the catalogue client's tests
 * give: the behaviour under test is what the app does with a 401, and that is a decision
 * `HttpURLConnection` makes as much as this code does.
 */
class KavitaClientTest {

    private lateinit var server: HttpServer
    private var tokenIsStale = false
    private var authentications = 0

    private fun client() = KavitaClient(
        KavitaAddress("http://localhost:${server.address.port}", "key"),
    )

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val bearer = exchange.requestHeaders.getFirst("Authorization")
            val body: String
            var status = 200

            when {
                path.endsWith("/Plugin/authenticate") -> {
                    authentications += 1
                    // The token minted after a staleness is fresh, so the retry works.
                    tokenIsStale = false
                    body = """{"username":"ada","token":"t"}"""
                }
                path.endsWith("/Server/server-info") -> body = """{"kavitaVersion":"0.8.3"}"""
                bearer == null || tokenIsStale -> {
                    status = 401
                    body = """{"message":"expired"}"""
                }
                path.endsWith("/Library/libraries") ->
                    body = """[{"id":1,"name":"Comics"},{"id":2,"name":"Books"}]"""
                path.endsWith("/Series/all-v2") ->
                    body = """[{"id":1,"name":"Tidal Reach","libraryId":1,"pages":24,"pagesRead":6}]"""
                path.endsWith("/Series/volumes") ->
                    body = """[{"id":10,"number":0,"chapters":[{"id":1,"number":"1","pages":8,"pagesRead":8}]},
                              {"id":11,"number":1,"name":"Volume 1","chapters":[]}]"""
                path.endsWith("/Search/search") ->
                    body = """{"series":[{"id":2,"name":"Tidal Reach"}]}"""
                else -> {
                    status = 404
                    body = """{"message":"no"}"""
                }
            }

            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
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
    fun connectingReportsTheAccountAndVersion() = runBlocking {
        val identity = client().connect()
        assertEquals("ada", identity.username)
        assertEquals(KavitaVersion(0, 8, 3), identity.version)
    }

    @Test
    fun librariesComeBackWithTheirNames() = runBlocking {
        assertEquals(listOf("Comics", "Books"), client().libraries().map { it.name })
    }

    @Test
    fun aSeriesReportsHowFarThroughItTheServerThinksYouAre() = runBlocking {
        assertEquals(0.25, client().series(1).first().fraction!!, 0.0001)
    }

    @Test
    fun looseChaptersAreDistinguishedFromAVolume() = runBlocking {
        // Without the distinction every such series shows a phantom "Volume 0".
        val volumes = client().volumes(1)
        assertTrue(volumes.first().isLooseChapters)
        assertFalse(volumes.last().isLooseChapters)
    }

    @Test
    fun aSearchResultWithNoPageCountsStillDecodes() = runBlocking {
        // Kavita's search carries identity, not progress. A decoder that insisted would turn
        // every search into "unexpected response".
        val found = client().search("tidal")
        assertEquals(listOf("Tidal Reach"), found.map { it.name })
        assertNull(found.first().fraction)
    }

    @Test
    fun anExpiredTokenIsRenewedAndTheRequestRetriedOnce() = runBlocking {
        val client = client()
        client.connect()
        authentications = 0
        tokenIsStale = true
        // The first attempt is refused, the token is renewed, and the retry succeeds --
        // without the caller seeing an error.
        assertEquals(2, client.libraries().size)
        assertEquals(1, authentications)
    }
}
