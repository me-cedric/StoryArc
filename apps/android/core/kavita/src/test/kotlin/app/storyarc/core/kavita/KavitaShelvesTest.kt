package app.storyarc.core.kavita

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * Putting a local reading list on a server, and taking it back off again.
 *
 * `collections-and-reading-lists` asks for a local list to be copied onto a server, and the
 * house makes an action of that shape undoable for ten seconds -- which for a list the server
 * now holds means asking the server to drop it. The same four claims iOS's
 * `KavitaShelvesTests` makes, in the same order.
 */
class KavitaShelvesTest {

    private lateinit var server: HttpServer

    /** What the stub was asked, so a test can check the verb and the address. */
    private var method: String? = null
    private var path: String? = null
    private var query: String? = null

    /** What the stub answers with, so one test can make the server refuse. */
    private var status = 200
    private var answer = """{"id":7,"title":"Crossover"}"""

    private fun client() = KavitaClient(
        KavitaAddress("http://localhost:${server.address.port}", "key"),
    )

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val requested = exchange.requestURI.path
            val body: String
            var code = 200
            if (requested.endsWith("/Plugin/authenticate")) {
                body = """{"username":"ada","token":"t"}"""
            } else {
                method = exchange.requestMethod
                path = requested
                query = exchange.requestURI.query
                code = status
                body = answer
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(code, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
    }

    @After
    fun stop() {
        server.stop(0)
    }

    @Test
    fun createAnswersWithTheServersOwnId() = runBlocking {
        // Everything that follows -- the entries, and the undo -- is addressed by it, so a
        // create that answered with nothing would leave the copy unable to finish.
        val made = client().createList("Crossover")
        assertEquals(7, made.id)
        assertEquals("Crossover", made.title)
    }

    @Test
    fun createPostsTheName() = runBlocking {
        client().createList("Crossover")
        assertEquals("POST", method)
        assertEquals("/api/ReadingList/create", path)
    }

    @Test
    fun deleteNamesTheList() = runBlocking {
        answer = "true"
        client().deleteList(7)
        assertEquals("DELETE", method)
        assertEquals("/api/ReadingList", path)
        assertEquals("readingListId=7", query)
    }

    @Test(expected = KavitaError.Http::class)
    fun aRefusedCreateThrows() {
        // The copy has to stop here. Carrying on would append entries to a list id that does
        // not exist, and report a copy that never happened.
        status = 500
        answer = """{"message":"no"}"""
        runBlocking { client().createList("Crossover") }
    }
}
