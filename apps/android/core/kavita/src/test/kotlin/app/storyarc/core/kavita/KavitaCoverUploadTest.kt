package app.storyarc.core.kavita

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.Base64
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Writing a cover back to the one Kavita route a normal reader may use.
 *
 * iOS's `KavitaCoverUploadTests` makes the same claims in the same order.
 */
class KavitaCoverUploadTest {

    private lateinit var server: HttpServer

    private var method: String? = null
    private var path: String? = null
    private var sent: String? = null
    private var requests = 0
    private var status = 200

    private fun client() = KavitaClient(
        KavitaAddress("http://localhost:${server.address.port}", "key"),
    )

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val body: String
            var code = 200
            if (exchange.requestURI.path.endsWith("/Plugin/authenticate")) {
                body = """{"username":"ada","token":"t"}"""
            } else {
                requests += 1
                method = exchange.requestMethod
                path = exchange.requestURI.path
                sent = exchange.requestBody.readBytes().decodeToString()
                body = "{}"
                code = status
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(code, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
    }

    @After
    fun stop() = server.stop(0)

    @Test
    fun `the cover is posted once, as base64, to the reading-list upload route`() = runBlocking {
        val image = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte())

        client().uploadReadingListCover(7, image)

        assertEquals("POST", method)
        assertEquals("/api/Upload/reading-list", path)
        assertEquals(1, requests)
        val posted = Json.parseToJsonElement(sent!!).jsonObject
        assertEquals(7, posted["id"]!!.jsonPrimitive.content.toInt())
        assertEquals(
            Base64.getEncoder().encodeToString(image),
            posted["url"]!!.jsonPrimitive.content,
        )
    }

    @Test
    fun `a picture above the ceiling is refused before anything is sent`() = runBlocking {
        // `design.md` fixes the ceiling at eight megabytes. Refused here rather than by the
        // server: a rejected body is a wasted upload on a connection a reader may be paying
        // for, and a 413 says nothing about which limit was passed.
        val image = ByteArray(KavitaClient.COVER_UPLOAD_CEILING + 1)

        val refused = runCatching { client().uploadReadingListCover(7, image) }.exceptionOrNull()

        assertEquals(KavitaError.ImageTooLarge, refused)
        assertEquals(0, requests)
    }

    @Test
    fun `an empty picture is refused too`() = runBlocking {
        val refused = runCatching {
            client().uploadReadingListCover(7, ByteArray(0))
        }.exceptionOrNull()

        assertEquals(KavitaError.ImageRejected, refused)
        assertEquals(0, requests)
    }

    @Test
    fun `an older Kavita without the route says so once`() = runBlocking {
        // `listing` reads a 404 as the route being absent and remembers it, so a reader on
        // an older server is told once rather than on every attempt.
        status = 404

        val refused = runCatching {
            client().uploadReadingListCover(7, byteArrayOf(0xFF.toByte()))
        }.exceptionOrNull()

        assertEquals(KavitaError.RouteMissing("Upload/reading-list"), refused)
    }

    @Test
    fun `a list the server promoted decodes as promoted`() {
        // The one ownership signal a client gets, and what `CoverWriteBack` reads.
        val json = Json { ignoreUnknownKeys = true }

        assertTrue(
            json.decodeFromString<KavitaReadingList>(
                """{"id":7,"title":"Staff picks","promoted":true}""",
            ).promoted,
        )
        assertFalse(
            json.decodeFromString<KavitaReadingList>("""{"id":8,"title":"Mine"}""").promoted,
        )
    }
}
