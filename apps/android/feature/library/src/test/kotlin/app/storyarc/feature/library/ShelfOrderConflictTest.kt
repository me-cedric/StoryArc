package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.persistence.KavitaProgressStore
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `collections-and-reading-lists` task 7.4: a pending server reorder must not overwrite a
 * server order that has moved since the reader dragged a row. Modelled on
 * `KavitaOpenFailureTest`'s mock server.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShelfOrderConflictTest {

    private val sourceId = "3E7F6C1C-0000-0000-0000-00000000CCCC"
    private var server: HttpServer? = null
    private var moved = false

    private fun store(): KavitaProgressStore =
        KavitaProgressStore.open(ApplicationProvider.getApplicationContext<Application>())
            .also { it.sent(it.unsent()) }

    /** @param serverOrder the chapter ids `ReadingList/items` answers with, in server order. */
    private fun serve(serverOrder: List<Int>): KavitaAddress {
        val started = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        started.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val body = when {
                path.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}"""
                path.endsWith("/ReadingList/items") ->
                    "[" + serverOrder.mapIndexed { index, chapter ->
                        """{"id":$chapter,"order":$index,"chapterId":$chapter,"seriesId":1,"volumeId":1,"libraryId":1}"""
                    }.joinToString(",") + "]"
                path.endsWith("/ReadingList/update-position") -> { moved = true; "true" }
                else -> null
            }?.toByteArray()
            exchange.sendResponseHeaders(if (body == null) 404 else 200, body?.size?.toLong() ?: -1)
            exchange.responseBody.use { stream -> body?.let(stream::write) }
        }
        started.start()
        server = started
        return KavitaAddress("http://localhost:${started.address.port}", "key")
    }

    @After
    fun stop() {
        server?.stop(0)
    }

    @Test
    fun `a baseline that still matches the server is sent as planned`() = runBlocking {
        val address = serve(serverOrder = listOf(1, 2, 3))
        val store = store()
        KavitaSync.reorder(store, address, sourceId, listId = 4, order = listOf(3, 1, 2), baseline = listOf(1, 2, 3))

        KavitaSync.flush(store, sourceId, address)

        assertTrue("the move the reader asked for was never sent", moved)
        assertTrue("a delivered order is still held, so it will be sent again", store.unsent().isEmpty())
    }

    @Test
    fun `a server that moved since the baseline is not overwritten`() = runBlocking {
        // The server answers 2,1,3 -- it moved since this device last saw 1,2,3.
        val address = serve(serverOrder = listOf(2, 1, 3))
        val store = store()
        var conflicts = 0
        KavitaSync.reorder(
            store,
            address,
            sourceId,
            listId = 4,
            order = listOf(3, 1, 2),
            baseline = listOf(1, 2, 3),
            onOrderConflict = { conflicts += 1 },
        )

        assertEquals(1, conflicts)
        assertTrue("the stale order was sent over the server's own change", !moved)
        assertTrue(
            "the stale order is still held, so a later flush would try to send it again",
            store.unsent().isEmpty(),
        )
    }

    @Test
    fun `a null baseline sends exactly as every caller did before this task`() = runBlocking {
        val address = serve(serverOrder = listOf(2, 1, 3))
        val store = store()
        var conflicts = 0
        KavitaSync.reorder(
            store,
            address,
            sourceId,
            listId = 4,
            order = listOf(3, 1, 2),
            onOrderConflict = { conflicts += 1 },
        )

        assertEquals(0, conflicts)
        assertTrue("a caller naming no baseline no longer sends its order", moved)
    }

    @Test
    fun `the first drag's baseline survives a second drag before either reaches the server`() = runBlocking {
        val store = store()
        KavitaSync.reorder(store, null, sourceId, listId = 4, order = listOf(2, 1, 3), baseline = listOf(1, 2, 3))
        KavitaSync.reorder(store, null, sourceId, listId = 4, order = listOf(3, 2, 1), baseline = listOf(2, 1, 3))

        assertEquals(listOf(3, 2, 1), store.unsent().single().order)
        assertEquals(
            "the second drag's own order replaced the first drag's baseline, so a server" +
                " change between the two would never be noticed",
            listOf(1, 2, 3),
            store.unsent().single().orderBaseline,
        )
    }
}
