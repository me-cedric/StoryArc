package app.storyarc.core.kavita

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * What a reading list and its entries carry off the wire, beyond a title.
 *
 * `collections-and-reading-lists` asks a list to say "how many entries are finished and where
 * the user's position is", and asks a shelf with no cover of its own to be drawn from what it
 * holds "unless the user sets a specific one". Both answers are already in the payload and
 * both were being discarded on the way in: `KavitaReadingListItem` kept six fields of
 * twenty-five and dropped the two progress numbers, and `KavitaReadingList` kept three of
 * twenty-four and dropped the cover and the lock beside it.
 *
 * The payloads below are the shape a live Kavita **0.9.1.4** answered with on 2026-09-10 --
 * every field name, every type, and the two nulls it sends. The names and the ids are
 * invented, because a fixture in a public repository should not be a reader's own library.
 *
 * The same two claims iOS's `KavitaReadingListDecodingTests` makes.
 */
class KavitaReadingListDecodingTest {

    private lateinit var server: HttpServer

    /** One list, as `ReadingList/lists` answers: an unlocked cover and a count. */
    private val lists = """
        [{"id":8,"title":"The long crossover","summary":"Read in publication order",
          "promoted":false,"coverImageLocked":false,"coverImage":"readinglist8.png",
          "primaryColor":"#20303f","secondaryColor":"#c8b28a","itemCount":77,
          "startingYear":2005,"startingMonth":4,"endingYear":2006,"endingMonth":1,
          "ageRating":0,"ownerUserName":"ada","sourcePath":null,"downloadUrl":null,
          "shaHash":null,"provider":0,"lastSyncCheckUtc":null,"lastSyncedUtc":null,
          "totalItemsAtImport":77,"tags":[],"canSync":false}]
    """.trimIndent()

    /** Three entries, as `ReadingList/items` answers: unread, part-read, finished. */
    private val items = """
        [{"id":1,"order":0,"chapterId":3103,"seriesId":312,"seriesName":"Lantern Green",
          "seriesSortName":"Lantern Green","seriesFormat":0,"pagesRead":0,"pagesTotal":22,
          "chapterNumber":"43","volumeNumber":"0","chapterTitleName":"Issue #43",
          "volumeId":516,"libraryId":2,"title":"Issue #43","libraryType":0,
          "libraryName":"Comics","releaseDate":"2005-04-01T00:00:00","readingListId":8,
          "lastReadingProgressUtc":null,"fileSize":41943040,"summary":null,
          "isSpecial":false,"chapter":{},"volume":{}},
         {"id":2,"order":1,"chapterId":3104,"seriesId":312,"seriesName":"Lantern Green",
          "seriesSortName":"Lantern Green","seriesFormat":0,"pagesRead":11,"pagesTotal":22,
          "chapterNumber":"44","volumeNumber":"0","chapterTitleName":"Issue #44",
          "volumeId":516,"libraryId":2,"title":"Issue #44","libraryType":0,
          "libraryName":"Comics","releaseDate":"2005-05-01T00:00:00","readingListId":8,
          "lastReadingProgressUtc":"2026-09-01T18:04:51","fileSize":41943040,"summary":null,
          "isSpecial":false,"chapter":{},"volume":{}},
         {"id":3,"order":2,"chapterId":3105,"seriesId":312,"seriesName":"Lantern Green",
          "seriesSortName":"Lantern Green","seriesFormat":0,"pagesRead":22,"pagesTotal":22,
          "chapterNumber":"45","volumeNumber":"0","chapterTitleName":"Issue #45",
          "volumeId":516,"libraryId":2,"title":"Issue #45","libraryType":0,
          "libraryName":"Comics","releaseDate":"2005-06-01T00:00:00","readingListId":8,
          "lastReadingProgressUtc":"2026-09-02T09:11:02","fileSize":41943040,"summary":null,
          "isSpecial":false,"chapter":{},"volume":{}}]
    """.trimIndent()

    private fun client() = KavitaClient(
        KavitaAddress("http://localhost:${server.address.port}", "key"),
    )

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val requested = exchange.requestURI.path
            val body = when {
                requested.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}"""
                requested.endsWith("/ReadingList/items") -> items
                else -> lists
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
    }

    @After
    fun stop() = server.stop(0)

    @Test
    fun `an entry carries the two numbers its read state is made of`() = runBlocking {
        val entries = client().readingListItems(8)

        assertEquals(listOf(0, 11, 22), entries.map { it.pagesRead })
        assertEquals(listOf(22, 22, 22), entries.map { it.pagesTotal })
    }

    @Test
    fun `a list carries the cover it has and whether a reader locked it`() = runBlocking {
        val shelf = client().readingLists().single()

        assertEquals("readinglist8.png", shelf.coverImage)
        assertFalse(
            "An unlocked cover is the case where the app composites its own.",
            shelf.coverImageLocked,
        )
        assertEquals(77, shelf.itemCount)
    }

    @Test
    fun `a server that says nothing about a cover leaves the shelf compositing`() = runBlocking {
        // An older Kavita sends neither field. The decoder ignores unknown keys, so the
        // defaults are what an older server means: no cover of its own, nothing locked.
        val bare = KavitaReadingList(id = 8, title = "The long crossover")

        assertEquals(null, bare.coverImage)
        assertFalse(bare.coverImageLocked)
        assertTrue(bare.itemCount == 0)
    }
}
