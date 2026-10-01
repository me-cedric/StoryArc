package app.storyarc.feature.library

import android.content.Context
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.persistence.ProgressStore
import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `collections-and-reading-lists` task 7.3, the two halves [ServerListContextTest]'s plain
 * unit tests cannot reach: [KavitaListScreen] actually arming [ServerListContext] when a row
 * opens, and [ServerListContext.fetch] actually reaching the server the way the screen's own
 * row does. Modelled on [KavitaOpenFailureTest]'s mock server.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ServerListContextIntegrationTest {

    @get:org.junit.Rule
    val compose = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private var server: HttpServer? = null

    private val corpus: File = File(
        requireNotNull(System.getProperty("storyarc.library.projectDir")) {
            "storyarc.library.projectDir is not set — see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    private val items = """
        [{"id":1,"order":0,"chapterId":10,"seriesId":312,"seriesName":"Lantern Green",
          "pagesRead":0,"pagesTotal":22,"volumeId":516,"libraryId":2,"title":"Issue #10"},
         {"id":2,"order":1,"chapterId":11,"seriesId":312,"seriesName":"Lantern Green",
          "pagesRead":0,"pagesTotal":22,"volumeId":516,"libraryId":2,"title":"Issue #11"}]
    """.trimIndent()

    private fun serve(chapterId: Int, bytes: ByteArray): Int {
        val started = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        started.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val body = when {
                path.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}""".toByteArray()
                path.endsWith("/ReadingList/items") -> items.toByteArray()
                path.endsWith("/Download/chapter") && exchange.requestURI.query?.contains("$chapterId") == true -> bytes
                else -> null
            }
            exchange.sendResponseHeaders(if (body == null) 404 else 200, body?.size?.toLong() ?: -1)
            exchange.responseBody.use { stream -> body?.let(stream::write) }
        }
        started.start()
        server = started
        return started.address.port
    }

    @After
    fun stop() {
        server?.stop(0)
        ServerListContext.clear()
    }

    @Test
    fun `opening the first entry arms the place at position zero, with both entries held`() {
        val comic = corpus.resolve("comics/single-page.cbz").readBytes()
        val port = serve(10, comic)
        val page = KavitaPage("server-1", "Attic", KavitaAddress("http://localhost:$port", "key"))

        compose.setContent {
            StoryArcTheme {
                KavitaListScreen(server = page, listId = 8, title = "Crossover", onOpen = { _, _ -> }, onBack = {})
            }
        }
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasText("Issue #10")).fetchSemanticsNodes().isNotEmpty()
        }
        // The title itself, where a reader taps: the row centre can fall on a row button.
        compose.onNodeWithText("Issue #10", useUnmergedTree = true).performClick()
        compose.waitUntil(10_000) { ServerListContext.current.value != null }

        val place = requireNonNullPlace()
        assertEquals("server-1", place.serverId)
        assertEquals(8, place.listId)
        assertEquals(0, place.position)
        assertEquals(listOf(10, 11), place.entries.map { it.chapterId })
        assertEquals(11, place.next?.chapterId)
        assertNull(place.previous)
    }

    @Test
    fun `fetching the next entry advances the place and returns the opened publication`() = runTest {
        val comic = corpus.resolve("comics/single-page.cbz").readBytes()
        val port = serve(11, comic)
        val address = KavitaAddress("http://localhost:$port", "key")
        val place = ServerListContext.Place(
            serverId = "server-2",
            serverAddress = address,
            listId = 8,
            entries = listOf(
                app.storyarc.core.kavita.KavitaReadingListItem(chapterId = 10, order = 0, title = "Issue #10"),
                app.storyarc.core.kavita.KavitaReadingListItem(chapterId = 11, order = 1, title = "Issue #11"),
            ),
            position = 0,
        )
        ServerListContext.opened(place)

        val fetched = ServerListContext.fetch(context, place, requireNotNull(place.next))

        assertTrue(fetched is ServerListContext.Fetch.Opened)
        assertEquals(1, ServerListContext.current.value?.position)
    }

    @Test
    fun `a server that refuses the fetch answers Failed, and the place does not move`() = runTest {
        // Every route 404s, which is what a server refusing the chapter looks like.
        val refusing = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        refusing.createContext("/") { exchange -> exchange.sendResponseHeaders(404, -1); exchange.close() }
        refusing.start()
        server = refusing
        val address = KavitaAddress("http://localhost:${refusing.address.port}", "key")
        val place = ServerListContext.Place(
            serverId = "server-3",
            serverAddress = address,
            listId = 8,
            entries = listOf(
                app.storyarc.core.kavita.KavitaReadingListItem(chapterId = 10, order = 0, title = "Issue #10"),
                app.storyarc.core.kavita.KavitaReadingListItem(chapterId = 11, order = 1, title = "Issue #11"),
            ),
            position = 0,
        )
        ServerListContext.opened(place)

        val fetched = ServerListContext.fetch(context, place, requireNotNull(place.next))

        assertTrue(
            "A refused fetch no longer names the entry it could not open.",
            (fetched as? ServerListContext.Fetch.Failed)?.message?.contains("Issue #11") == true,
        )
        assertEquals(0, ServerListContext.current.value?.position)
    }

    @Test
    fun `taking the offered entry fetches it, seeds the server's position and advances the place`() = runTest {
        // Tasks 7.3 and 7.14: the offer is a placeholder with no file, so taking it fetches.
        val comic = corpus.resolve("comics/single-page.cbz").readBytes()
        val port = serve(11, comic)
        val serverId = UUID.randomUUID().toString()
        val place = ServerListContext.Place(
            serverId = serverId,
            serverAddress = KavitaAddress("http://localhost:$port", "key"),
            listId = 8,
            entries = listOf(
                KavitaReadingListItem(chapterId = 10, order = 0, title = "Issue #10"),
                KavitaReadingListItem(chapterId = 11, order = 1, title = "Issue #11", pagesRead = 5, pagesTotal = 22),
            ),
            position = 0,
        )
        ServerListContext.opened(place)
        val reading = place.placeholder(place.entries[0])
        val offered = requireNotNull(ServerListContext.next(reading))
        val progress = ProgressStore.inMemory(context)

        val opened = ServerListContext.open(context, offered, progress)

        assertTrue("Taking the offer did not fetch the entry it named.", opened is ServerListContext.Fetch.Opened)
        assertEquals(1, ServerListContext.current.value?.position)
        val publication = (opened as ServerListContext.Fetch.Opened).publication
        assertTrue(
            "The taken entry opened without the position the server reported for it.",
            progress.progress(publication.identity) != null,
        )
    }

    @Test
    fun `an offer that names no entry of the current list opens nothing`() = runTest {
        val place = ServerListContext.Place(
            serverId = UUID.randomUUID().toString(),
            serverAddress = KavitaAddress("http://localhost:1", "key"),
            listId = 8,
            entries = listOf(KavitaReadingListItem(chapterId = 10, order = 0, title = "Issue #10")),
            position = 0,
        )
        ServerListContext.opened(place)
        val elsewhere = place.copy(serverId = UUID.randomUUID().toString()).placeholder(place.entries[0])

        assertNull(ServerListContext.open(context, elsewhere, progress = null))
    }

    private fun requireNonNullPlace() = requireNotNull(ServerListContext.current.value)
}
