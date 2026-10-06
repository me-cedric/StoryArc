package app.storyarc.core.catalogue

import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.CoverLookupProvider
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The lookup, against a transport that records what it was asked.
 *
 * iOS's `CoverLookupClientTests` makes the same claims against a stubbed `URLProtocol`.
 */
class CoverLookupClientTest {

    @get:Rule
    val folder = TemporaryFolder()

    /** Every request the client made, which is what the egress assertions read. */
    private val asked = mutableListOf<CoverFetch>()

    private fun transport(status: Int = 200, body: String = "", url: String? = null) =
        CoverTransport { request ->
            asked += request
            CoverFetched(status, body.toByteArray(), url ?: request.url)
        }

    private fun cache(): CoverLookupCache = CoverLookupCache(file())

    private fun file(): File = folder.newFile()

    private fun client(
        enabled: Boolean,
        cache: CoverLookupCache = cache(),
        transport: CoverTransport = transport(),
    ) = CoverLookupClient({ enabled }, cache, transport)

    @Test
    fun `nothing is asked while the setting is off`() = runBlocking {
        // `cover-art`: "a reader has never opened the cover-lookup setting ... no cover
        // request is made to any third party". Task 3.5 asks for exactly this assertion.
        val found = client(enabled = false)
            .cover("pub", CoverIdentifier.Isbn("9780141187761"))

        assertNull(found)
        assertTrue(asked.isEmpty())
    }

    @Test
    fun `a title search is silent too while the setting is off`() = runBlocking {
        val candidates = client(enabled = false).candidates("Fine Print")

        assertTrue(candidates.isEmpty())
        assertTrue(asked.isEmpty())
    }

    @Test
    fun `a provider that answers with a picture gives back its address`() = runBlocking {
        val found = client(enabled = true, transport = transport(url = "https://art/1.jpg"))
            .cover("pub", CoverIdentifier.Isbn("9780141187761"))

        assertEquals("https://art/1.jpg", found)
    }

    @Test
    fun `Audnexus answers with a document, and the image field is read out of it`() =
        runBlocking {
            val body = """{"asin":"B08G9PRS1K","image":"https://m.media-amazon.com/images/I/c.jpg"}"""
            val found = client(enabled = true, transport = transport(body = body))
                .cover("pub", CoverIdentifier.AudibleAsin("B08G9PRS1K"))

            assertEquals("https://m.media-amazon.com/images/I/c.jpg", found)
        }

    @Test
    fun `an answer naming a host the setting does not name is not followed`() = runBlocking {
        // A provider's answer can name any address at all. Fetched, it would send a request to
        // a host the reader never agreed to, which non-negotiable 2 forbids.
        for (image in listOf("https://tracker.example/c.jpg", "http://m.media-amazon.com/c.jpg")) {
            val body = """{"asin":"B08G9PRS1K","image":"$image"}"""
            val found = client(enabled = true, transport = transport(body = body))
                .cover("pub", CoverIdentifier.AudibleAsin("B08G9PRS1K"))

            assertEquals("Followed $image", null, found)
        }
    }

    @Test
    fun `the image route refuses an unlisted host before anything is sent`() = runBlocking {
        var sent = false
        val client = client(enabled = true, transport = CoverTransport { sent = true; null })

        assertEquals(null, client.image("https://tracker.example/c.jpg"))
        assertEquals(false, sent)
    }

    @Test
    fun `one publication is asked about once, whatever the answer was`() = runBlocking {
        // `cover-art`: "the same publication is never looked up twice, because a provider
        // that asks not to be crawled is entitled to that".
        val client = client(enabled = true, transport = transport(status = 404))

        client.cover("pub", CoverIdentifier.Isbn("9780141187761"))
        client.cover("pub", CoverIdentifier.Isbn("9780141187761"))

        assertEquals(1, asked.size)
    }

    @Test
    fun `a refusal is quiet, so the cover is unchanged and nothing throws`() = runBlocking {
        // 403, 404, 429 or silence all come back the same way, because they are the same
        // outcome for the reader: the publication keeps the cover it had.
        for (status in listOf(403, 404, 429, 500)) {
            val found = client(enabled = true, transport = transport(status = status))
                .cover("pub", CoverIdentifier.Isbn("9780141187761"))
            assertNull("status $status should answer null rather than throw", found)
        }
    }

    @Test
    fun `silence is quiet too`() = runBlocking {
        val silent = CoverTransport { request ->
            asked += request
            null
        }
        val found = client(enabled = true, transport = silent)
            .cover("pub", CoverIdentifier.Isbn("9780141187761"))

        assertNull(found)
        assertEquals(1, asked.size)
    }

    @Test
    fun `a publication can be asked again once its answer is forgotten`() = runBlocking {
        // The escape hatch a cached 429 needs: the provider was asking for later, and a
        // reader asking by hand is the later. Nothing else re-asks.
        val shared = cache()
        val client = client(enabled = true, cache = shared, transport = transport(status = 429))

        client.cover("pub", CoverIdentifier.Isbn("9780141187761"))
        shared.forget("pub")
        client.cover("pub", CoverIdentifier.Isbn("9780141187761"))

        assertEquals(2, asked.size)
    }

    @Test
    fun `an answer survives the cache being made again from the same file`() {
        val file = file()
        val answer = CoverLookupAnswer(CoverLookupProvider.OPEN_LIBRARY, "https://art/1.jpg")

        CoverLookupCache(file).record(answer, "pub")

        assertEquals(answer, CoverLookupCache(file).answer("pub"))
    }

    @Test
    fun `a refusal is recorded as well as a hit`() = runBlocking {
        val shared = cache()

        client(enabled = true, cache = shared, transport = transport(status = 404))
            .cover("pub", CoverIdentifier.Isbn("9780141187761"))

        val recorded = shared.answer("pub")
        assertNull(recorded?.imageUrl)
        assertEquals(CoverLookupProvider.OPEN_LIBRARY, recorded?.provider)
    }
}
