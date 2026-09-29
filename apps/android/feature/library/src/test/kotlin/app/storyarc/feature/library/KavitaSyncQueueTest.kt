package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.KavitaUnsent
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A report that reaches the server drops what an earlier, offline read had held.
 *
 * The field defect: an offline read holds page 10; an online session later reports page 20;
 * a subsequent flush still sends the held page 10 and moves the server back. iOS's
 * `KavitaSyncQueueTests` asserts the same case.
 *
 * `sdk = [34]` for the reason `KavitaCardFactsTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaSyncQueueTest {

    private lateinit var server: HttpServer

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val body = if (path.endsWith("/Plugin/authenticate")) {
                """{"username":"ada","token":"t"}"""
            } else {
                "{}"
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
    }

    @After
    fun stop() {
        server.stop(0)
    }

    private fun store() =
        KavitaProgressStore.open(ApplicationProvider.getApplicationContext<Context>())

    private fun origin(sourceId: String) = KavitaOrigin(
        sourceId = sourceId,
        libraryId = 1,
        seriesId = 7,
        volumeId = 3,
        chapterId = 12,
    )

    @Test
    fun `a page held while offline is dropped once the same chapter reports successfully`() =
        runBlocking {
            val store = store()
            val origin = origin("this-server")
            // The offline read: page 10 could not reach the server, so it sits in the queue.
            store.hold(KavitaUnsent(origin, page = 10))
            assertEquals(1, store.unsent().size)

            // The online session: page 20, reported straight to a server that answers.
            val address = KavitaAddress("http://localhost:${server.address.port}", "key")
            KavitaSync.report(store, address, origin, page = 20)

            assertTrue(
                "the stale held page must not survive a successful report",
                store.unsent().isEmpty(),
            )
        }

    @Test
    fun `a report that fails still holds its own page alongside another server's`() = runBlocking {
        val store = store()
        store.hold(KavitaUnsent(origin("other-server"), page = 3))

        // No address at all is the same "not reachable" branch a network failure takes.
        KavitaSync.report(store, null, origin("this-server"), page = 7)

        assertEquals(2, store.unsent().size)
        assertEquals(setOf(3, 7), store.unsent().map { it.page }.toSet())
    }
}
