package app.storyarc.feature.library

import app.storyarc.core.catalogue.CoverFetch
import app.storyarc.core.catalogue.CoverFetched
import app.storyarc.core.catalogue.CoverLookupCache
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.catalogue.CoverTransport
import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.net.URI
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The lookup rung's three trust rules, asserted through the rung the ladder calls.
 *
 * Task 6.1 of `cover-for-every-publication`, which keeps the wave 11 review's rules: the rung
 * reaches only the hosts the setting names, reads at most 8 MB of an answer (asserted beside
 * the transport, in `:core:catalogue`), and never runs while the setting is off. iOS's
 * `CoverLookupRungTests` is the twin of this file.
 */
class CoverLookupRungTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val asked = mutableListOf<CoverFetch>()
    private var identified = 0
    private val isbn = CoverIdentifier.Isbn("9780141187761")
    private val publication = Publication(
        identity = PublicationIdentity(contentDigest = "digest", normalizedPath = "/books/fine-print.epub"),
        format = PublicationFormat.EPUB,
        displayTitle = "Fine Print",
        origin = MetadataOrigin.INFERRED,
    )

    private fun rung(
        enabled: Boolean,
        identifier: CoverIdentifier? = isbn,
        answer: (CoverFetch) -> CoverFetched = { CoverFetched(200, "jpeg".toByteArray(), it.url) },
    ): CoverLookupRung {
        val transport = CoverTransport { request ->
            asked += request
            answer(request)
        }
        val client = CoverLookupClient({ enabled }, CoverLookupCache(folder.newFile()), transport)
        return CoverLookupRung(
            isEnabled = { enabled },
            client = client,
            identify = {
                identified++
                identifier
            },
        )
    }

    @Test
    fun `one publication with one identifier asks one provider once while the switch is on`() =
        runBlocking {
            val rung = rung(enabled = true)

            val first = rung.picture(publication)
            val second = rung.picture(publication)

            assertArrayEquals("jpeg".toByteArray(), first)
            assertArrayEquals("jpeg".toByteArray(), second)
            assertEquals(
                listOf("https://covers.openlibrary.org/b/isbn/9780141187761-L.jpg?default=false"),
                asked.map { it.url },
            )
        }

    @Test
    fun `the request carries the identifier and nothing else`() = runBlocking {
        rung(enabled = true).picture(publication)

        val request = asked.single()
        assertEquals("GET", request.method)
        assertNull(request.body)
        assertTrue(!request.url.contains("fine-print") && !request.url.contains("digest"))
    }

    @Test
    fun `nothing is read and nothing is asked while the switch is off`() = runBlocking {
        val found = rung(enabled = false).picture(publication)

        assertNull(found)
        assertTrue(asked.isEmpty())
        assertEquals("the file is not even opened for an identifier", 0, identified)
    }

    @Test
    fun `a publication with no identifier asks nothing`() = runBlocking {
        val found = rung(enabled = true, identifier = null).picture(publication)

        assertNull(found)
        assertTrue(asked.isEmpty())
    }

    @Test
    fun `an answer that names a host the setting does not name is not followed`() = runBlocking {
        val asin = CoverIdentifier.AudibleAsin("B08G9PRS1K")
        val rung = rung(enabled = true, identifier = asin) {
            CoverFetched(200, """{"image":"https://tracker.example/c.jpg"}""".toByteArray(), it.url)
        }

        val found = rung.picture(publication)

        assertNull(found)
        assertEquals(listOf("api.audnex.us"), asked.map { URI(it.url).host })
    }

    @Test
    fun `a refusal leaves the cover as it was and is not asked again`() = runBlocking {
        val rung = rung(enabled = true) { CoverFetched(429, ByteArray(0), it.url) }

        assertNull(rung.picture(publication))
        assertNull(rung.picture(publication))

        assertEquals(1, asked.size)
    }
}
