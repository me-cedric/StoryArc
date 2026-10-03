package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.PublicationStatus
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `library-browsing` (D36): the status a Kavita server reports for a series is carried onto
 * every row the library reads from that series, through [KavitaContributor.page].
 *
 * iOS's `KavitaContributorStatusTests` makes the same claims. `sdk = [34]` for the reason
 * `KavitaCardFactsTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaContributorStatusTest {

    private fun statuses(metadata: String?): List<PublicationStatus?> {
        val server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val (code, body) = when {
                path.endsWith("/Plugin/authenticate") -> 200 to """{"username":"ada","token":"t"}"""
                path.endsWith("/Series/recently-added-v2") ->
                    200 to """[{"id":312,"name":"Lantern Green","libraryId":7}]"""
                path.endsWith("/Series/metadata") -> if (metadata == null) 500 to "" else 200 to metadata
                else -> 200 to """[{"id":55,"number":1,"chapters":[{"id":3103,"number":"43","pages":22},
                    {"id":3104,"number":"44","pages":20}]}]"""
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(code, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val client = KavitaClient(KavitaAddress("http://localhost:${server.address.port}", "key"))
            val page = runBlocking { KavitaContributor.page(UUID.randomUUID(), client, 1) }
            return page.slice.publications.map { it.status }
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun `every chapter row carries the status its server reports for the series`() {
        assertEquals(
            listOf(PublicationStatus.COMPLETED, PublicationStatus.COMPLETED),
            statuses("""{"seriesId":312,"publicationStatus":2}"""),
        )
    }

    @Test
    fun `a status the server could not give leaves the rows without one, and keeps them`() {
        assertEquals(listOf(null, null), statuses(null))
    }
}
