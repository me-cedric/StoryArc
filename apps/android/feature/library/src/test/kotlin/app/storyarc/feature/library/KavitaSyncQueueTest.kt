package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.KavitaUnsent
import app.storyarc.core.persistence.ProgressStore
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

    private fun progressStore() = ProgressStore.inMemory(ApplicationProvider.getApplicationContext())

    @Test
    fun `a successful report stamps the local record as synchronised`() = runBlocking {
        val store = store()
        val origin = origin("stamp-server")
        val progress = progressStore()
        val identity = PublicationIdentity(normalizedPath = "/books/one.cbz")
        store.remember(identity.stableId, origin)
        progress.save(
            ReadingProgress(identity = identity, position = ReadingPosition.Page(19, 20), updatedAtEpochMillis = 0),
        )

        val address = KavitaAddress("http://localhost:${server.address.port}", "key")
        KavitaSync.report(store, address, origin, page = 19, progress = progress)

        val found = progress.progress(identity)
        assertEquals(ReadingPosition.Page(19, 20).fraction, found?.syncedPosition?.fraction)
    }

    @Test
    fun `a finished local record that wins a conflict is queued as a mark, not a page`() = runBlocking {
        val store = store()
        val chapterOrigin = origin("mark-queue-server")
        val progress = progressStore()
        val identity = PublicationIdentity(normalizedPath = "/books/three.cbz")
        store.remember(identity.stableId, chapterOrigin)
        progress.save(
            ReadingProgress(
                identity = identity,
                position = ReadingPosition.Page(9, 10),
                isFinished = true,
                updatedAtEpochMillis = 0,
            ),
        )

        // No address: the queue is the whole assertion here, not a network round trip.
        KavitaSync.pull(
            listOf(KavitaChapter(id = chapterOrigin.chapterId, number = "1", pages = 10, pagesRead = 2)),
            store,
            progress,
        )

        val held = store.unsent().first()
        assertEquals(true, held.mark)
        assertEquals(chapterOrigin.chapterId, held.origin.chapterId)
    }

    @Test
    fun `a held position stamps its local record too, once flush delivers it`() = runBlocking {
        val store = store()
        val origin = origin("flush-stamp-server")
        val progress = progressStore()
        val identity = PublicationIdentity(normalizedPath = "/books/two.cbz")
        store.remember(identity.stableId, origin)
        progress.save(
            ReadingProgress(identity = identity, position = ReadingPosition.Page(9, 10), updatedAtEpochMillis = 0),
        )
        store.hold(KavitaUnsent(origin, page = 9))

        val address = KavitaAddress("http://localhost:${server.address.port}", "key")
        KavitaSync.flush(store, origin.sourceId, address, progress)

        val found = progress.progress(identity)
        assertEquals(ReadingPosition.Page(9, 10).fraction, found?.syncedPosition?.fraction)
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
