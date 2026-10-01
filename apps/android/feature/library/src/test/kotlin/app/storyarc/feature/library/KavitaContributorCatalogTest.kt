package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.persistence.KavitaProgressStore
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 12.1: a browse catalogues the origin of every chapter it lists, through
 * [KavitaContributor.page], the read the library itself makes.
 *
 * iOS's `KavitaContributorCatalogOriginTests` makes the same claim. `sdk = [34]` for the
 * reason `KavitaCardFactsTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaContributorCatalogTest {

    @Test
    fun `a browse catalogues every chapter it lists, and claims no open`() {
        val server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            val body = when {
                path.endsWith("/Plugin/authenticate") -> """{"username":"ada","token":"t"}"""
                path.endsWith("/Series/recently-added-v2") ->
                    """[{"id":312,"name":"Lantern Green","libraryId":7}]"""
                else -> """[{"id":55,"number":1,"chapters":[{"id":3103,"number":"43","pages":22}]}]"""
            }
            val bytes = body.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(200, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
        try {
            val store = KavitaProgressStore.open(ApplicationProvider.getApplicationContext<Context>())
            val client = KavitaClient(KavitaAddress("http://localhost:${server.address.port}", "key"))

            val page = runBlocking { KavitaContributor.page(UUID.randomUUID(), client, 1, store) }

            val id = page.slice.publications.first().id
            assertEquals(55, store.catalogOrigin(id)?.volumeId)
            assertNull(store.origin(id))
        } finally {
            server.stop(0)
        }
    }
}
