package app.storyarc.feature.library

import android.content.Context
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.kavita.KavitaAddress
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A reading-list entry that does not open says which entry, and why.
 *
 * The field report: a comic opened from a Kavita reading list "showed a loader for ever". A
 * failed open cleared the row's spinner and said nothing else. These tests tap a real row of
 * [KavitaListScreen] against a local server and read the snackbar the tap leaves.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class KavitaOpenFailureTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private var server: HttpServer? = null

    /** One entry, in the shape `ReadingList/items` answers. */
    private val items = """
        [{"id":1,"order":0,"chapterId":3103,"seriesId":312,"seriesName":"Lantern Green",
          "pagesRead":0,"pagesTotal":22,"volumeId":516,"libraryId":2,"title":"Issue #43"}]
    """.trimIndent()

    /** A server that lists the entry, and answers the chapter download with [chapter]. */
    private fun serve(chapter: (com.sun.net.httpserver.HttpExchange) -> Unit): Int {
        val started = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        started.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            if (path.endsWith("/Download/chapter")) return@createContext chapter(exchange)
            val body = when {
                path.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}"""
                path.endsWith("/ReadingList/items") -> items
                else -> null
            }?.toByteArray()
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
    }

    private fun tapTheEntry(port: Int) {
        val page = KavitaPage("kavita-open", "Attic", KavitaAddress("http://localhost:$port", "key"))
        compose.setContent {
            StoryArcTheme {
                KavitaListScreen(server = page, listId = 8, title = "Crossover", onOpen = { _, _ -> }, onBack = {})
            }
        }
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasText("Issue #43")).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Issue #43").performClick()
    }

    private fun waitForSnackbar(expected: String) {
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasText(expected)).fetchSemanticsNodes().isNotEmpty()
        }
        assertTrue(compose.onAllNodes(hasText(expected)).fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun `a download the server refuses names the entry and the server`() {
        tapTheEntry(serve { exchange -> exchange.sendResponseHeaders(500, -1); exchange.close() })

        waitForSnackbar(
            context.getString(R.string.kavita_open_failed, "Issue #43") + " " +
                context.getString(R.string.kavita_open_not_sent, "Attic"),
        )
    }

    @Test
    fun `a file the reader cannot read says so rather than blaming the server`() {
        tapTheEntry(
            serve { exchange ->
                val bytes = "not a comic".toByteArray()
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            },
        )

        waitForSnackbar(
            context.getString(R.string.kavita_open_failed, "Issue #43") + " " +
                context.getString(R.string.kavita_open_unreadable, "Attic"),
        )
    }
}
