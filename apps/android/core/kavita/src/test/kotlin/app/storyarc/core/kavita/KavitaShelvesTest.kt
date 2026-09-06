package app.storyarc.core.kavita

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The writes a reader's shelf makes to a server: making a list, dropping it again, moving one
 * of its entries, and making a collection.
 *
 * `collections-and-reading-lists` asks for a local list to be copied onto a server, and the
 * house makes an action of that shape undoable for ten seconds -- which for a list the server
 * now holds means asking the server to drop it. The same requirement makes a reading list's
 * order its meaning and asks a new order to be "sent to the server", and lets a new shelf be
 * kept "on a server if the user chooses one that supports collections".
 *
 * The same nine claims iOS's `KavitaShelvesTests` makes, in the same order.
 */
class KavitaShelvesTest {

    private lateinit var server: HttpServer

    /** What the stub was asked, so a test can check the verb and the address. */
    private var method: String? = null
    private var path: String? = null
    private var query: String? = null

    /** What was posted, so a test can check the fields Kavita reads rather than only the
     * address they were sent to. */
    private var sent: String? = null

    /** Where a read went, so a test can check the route and not only the answer. */
    private var readPath: String? = null
    private var readQuery: String? = null

    /** What a GET is answered with, which for a collection create is the read-back. */
    private var listing = """[{"id":4,"title":"Attic"}]"""

    /** What a GET after the create is answered with, when a test wants a different listing. */
    private var listingAfter: String? = null

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
            } else if (exchange.requestMethod == "GET") {
                // Kept apart from `method` and `path`, which the create tests read as "which
                // side of the create is this", and which a read must therefore leave alone.
                readPath = requested
                readQuery = exchange.requestURI.query
                // `method` is set by the branch below, so it says which side of the create
                // this read is on -- which is what lets a test change what the server holds.
                body = if (method == null) listing else listingAfter ?: listing
            } else {
                method = exchange.requestMethod
                path = requested
                query = exchange.requestURI.query
                sent = exchange.requestBody.readBytes().decodeToString()
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
    fun collectedAsksTheRouteKavitaPublishes() = runBlocking {
        // `Collection/series` is in no shipped Kavita: absent from the published
        // `openapi.json` of v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4, and 404 on a live
        // 0.9.1.4. `Series/series-by-collection` is in all five and answered 200 on that same
        // server. `Collection/all-series` is not the replacement -- it takes a `seriesId`, so
        // it answers which collections hold one series, the other question. iOS's
        // `KavitaShelvesTests` makes the same claim, and `scripts/kavita-server.mjs
        // --self-test` the server's half of it.
        listing = "[]"
        client().collected(4)
        assertEquals("/api/Series/series-by-collection", readPath)
        assertEquals("collectionId=4", readQuery)
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

    @Test
    fun moveNamesTheEntryAndBothPositions() = runBlocking {
        // Kavita moves by position and by entry together. A client that sent one without the
        // other would move whatever happens to sit there now.
        answer = "{}"
        client().moveInList(7, item = 3, from = 2, to = 0)
        assertEquals("POST", method)
        assertEquals("/api/ReadingList/update-position", path)
        assertTrue(sent.orEmpty().contains(""""readingListId":7"""))
        assertTrue(sent.orEmpty().contains(""""readingListItemId":3"""))
        assertTrue(sent.orEmpty().contains(""""fromPosition":2"""))
        assertTrue(sent.orEmpty().contains(""""toPosition":0"""))
    }

    @Test(expected = KavitaError.Http::class)
    fun aRefusedMoveThrows() {
        // Which is what lets the order stay queued: a caller that swallowed this would drop
        // the reader's order on the floor and say nothing.
        status = 400
        answer = """{"message":"no"}"""
        runBlocking { client().moveInList(7, item = 3, from = 2, to = 0) }
    }

    @Test
    fun createCollectionPostsTheNameWithNoTag() = runBlocking {
        answer = "{}"
        val made = client().createCollection("Attic")
        assertEquals("POST", method)
        assertEquals("/api/Collection/update-for-series", path)
        assertTrue(sent.orEmpty().contains(""""collectionTagId":0"""))
        assertTrue(sent.orEmpty().contains(""""collectionTagTitle":"Attic""""))
        // Read back, because the bulk-add answers with nothing and the id is what everything
        // after this is addressed by.
        assertEquals(4, made.id)
        assertEquals("Attic", made.title)
    }

    @Test
    fun createCollectionAnswersWithTheMintedId() = runBlocking {
        // Kavita lists collections by title, so two of one name have no reliable order and a
        // read-back that matched on the name could address somebody else's collection.
        answer = "{}"
        listing = """[{"id":4,"title":"Attic"}]"""
        listingAfter = """[{"id":9,"title":"Attic"},{"id":4,"title":"Attic"}]"""
        assertEquals(9, client().createCollection("Attic").id)
    }

    @Test(expected = KavitaError.UnexpectedResponse::class)
    fun aCollectionTheServerNeverListsThrows() {
        answer = "{}"
        listing = "[]"
        runBlocking { client().createCollection("Attic") }
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
