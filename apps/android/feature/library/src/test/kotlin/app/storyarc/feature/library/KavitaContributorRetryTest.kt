package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A series whose volumes call keeps failing is not lost -- it is retried.
 *
 * Package `f4-read-core`, decision text D-none (task 22.1's own corrected scope, item 4): "A
 * series that fails its volumes call two times is still lost until the next full read." A
 * continuation page is asked for once, so a series it could not read was gone for good until
 * the whole first-slice-and-continuation read started over. [KavitaContributor.retry] is the
 * second chance, fed by the ids [KavitaContributor.page] now reports in `failedSeriesIds`
 * instead of silently treating a failed series the same as an empty one.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaContributorRetryTest {

    /** A server whose `Series/volumes` answers 500 the first [failures] times, then succeeds. */
    private fun server(failures: Int): Pair<HttpServer, AtomicInteger> {
        val volumesCalls = AtomicInteger(0)
        val server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val (code, body) = when {
                path.endsWith("/Plugin/authenticate") -> 200 to """{"username":"ada","token":"t"}"""
                path.endsWith("/Series/recently-added-v2") ->
                    200 to """[{"id":312,"name":"Lantern Green","libraryId":7}]"""
                path == "/api/Series/312" -> 200 to """{"id":312,"name":"Lantern Green","libraryId":7}"""
                path.endsWith("/Series/volumes") ->
                    if (volumesCalls.getAndIncrement() < failures) 500 to "" else
                        200 to """[{"id":55,"number":1,"chapters":[{"id":3103,"number":"43","pages":22}]}]"""
                else -> 404 to ""
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(code, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        return server to volumesCalls
    }

    private fun client(server: HttpServer) =
        KavitaClient(KavitaAddress("http://localhost:${server.address.port}", "key"))

    @Test
    fun `a series whose volumes call fails twice is reported, not silently emptied`() {
        val (server, _) = server(failures = 2)
        try {
            val page = runBlocking { KavitaContributor.page(UUID.randomUUID(), client(server), 1) }

            assertTrue(page.slice.publications.isEmpty())
            assertEquals(listOf(312), page.failedSeriesIds)
            // The page still counted the series as read: the server's own page cursor moved
            // past it, so asking for the same page again is not this page's job.
            assertEquals(1, page.seriesRead)
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun `a series whose volumes call fails only once still lands in the page, failing nobody`() {
        val (server, _) = server(failures = 1)
        try {
            val page = runBlocking { KavitaContributor.page(UUID.randomUUID(), client(server), 1) }

            assertEquals(1, page.slice.publications.size)
            assertTrue(page.failedSeriesIds.isEmpty())
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun `retry succeeds once the server does, and drops the series from what still fails`() {
        // Two failures already happened on the page this id came from, so by the time retry
        // runs, one more success is what the server owes it.
        val (server, _) = server(failures = 0)
        try {
            val source = UUID.randomUUID()
            val result = runBlocking { KavitaContributor.retry(source, client(server), setOf(312)) }

            assertEquals(1, result.publications.size)
            assertEquals("Lantern Green #43", result.publications.single().displayTitle)
            assertTrue(result.stillFailed.isEmpty())
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun `a series the server still refuses stays in what failed, not in the library`() {
        val (server, _) = server(failures = Int.MAX_VALUE)
        try {
            val source = UUID.randomUUID()
            val result = runBlocking { KavitaContributor.retry(source, client(server), setOf(312)) }

            assertTrue(result.publications.isEmpty())
            assertEquals(listOf(312), result.stillFailed)
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun `retriedOnceOrNull tells a failure from a real empty answer, which retriedOnce cannot`() = runBlocking {
        var calls = 0
        val failedTwice = KavitaContributor.retriedOnceOrNull<Int> {
            calls += 1
            throw RuntimeException("still down")
        }

        assertEquals(2, calls)
        assertEquals(null, failedTwice)
    }
}
