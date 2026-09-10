package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PublicationFormat
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What one entry of a catalogue looks like as a row.
 *
 * `library-browsing` asks a catalogue's publications to sit in the library beside every
 * other source's, "distinguished by what it can do rather than by where it sits".
 *
 * The one thing this must not do is keep an acquisition address: `sources` forbids a cached
 * catalogue holding a credential, and an OPDS acquisition link can carry a key in its query.
 * A row keeps the entry's id and nothing that reaches disk.
 */
class OpdsContributorTest {

    private val source = UUID.randomUUID()

    private fun entry(
        id: String = "urn:uuid:1",
        title: String = "Tidal Reach",
        series: String? = null,
        index: Double? = null,
        type: String? = "application/vnd.comicbook+zip",
    ) = OpdsEntry(
        id = id,
        title = title,
        series = series,
        seriesIndex = index,
        acquisitions = type?.let {
            listOf(
                OpdsAcquisition(
                    href = "https://example/get?key=secret",
                    mediaType = it,
                    kind = OpdsAcquisition.Kind.OPEN,
                ),
            )
        }.orEmpty(),
    )

    @Test
    fun `an entry is identified by its catalogue and its own id`() {
        val row = OpdsContributor.publication(source, entry())!!

        assertEquals(source, row.identity.serverIdentifier?.sourceId)
        assertEquals("opds:urn:uuid:1", row.identity.serverIdentifier?.remoteId)
        assertNull(row.identity.normalizedPath)
    }

    @Test
    fun `no acquisition address survives into the row`() {
        val row = OpdsContributor.publication(source, entry())!!

        // Every field that reaches the cache, checked for the secret the link carried.
        val written = listOfNotNull(
            row.displayTitle,
            row.series,
            row.number,
            row.summary,
            row.identity.serverIdentifier?.remoteId,
            row.identity.normalizedPath,
        ) + row.authors
        assertEquals(emptyList<String>(), written.filter { it.contains("secret") })
    }

    @Test
    fun `a navigation entry is not a publication`() {
        // A feed's entries are not all books, and one with no acquisition is a way further
        // in. It belongs to the browser.
        assertNull(OpdsContributor.publication(source, entry(type = null)))
    }

    @Test
    fun `an entry the app cannot open is not listed`() {
        assertNull(OpdsContributor.publication(source, entry(type = "application/x-mobipocket")))
    }

    @Test
    fun `each media type files under a format the filter can show`() {
        fun format(type: String) =
            OpdsContributor.publication(source, entry(type = type))?.format

        assertEquals(PublicationFormat.CBZ, format("application/vnd.comicbook+zip"))
        assertEquals(PublicationFormat.CBR, format("application/vnd.comicbook-rar"))
        assertEquals(PublicationFormat.EPUB, format("application/epub+zip"))
        assertEquals(PublicationFormat.PDF, format("application/pdf"))
    }

    @Test
    fun `a series index reads as an issue number`() {
        assertEquals("3", OpdsContributor.publication(source, entry(index = 3.0))?.number)
        assertEquals("3.5", OpdsContributor.publication(source, entry(index = 3.5))?.number)
    }

    @Test
    fun `the catalogue owns the metadata it supplied`() {
        assertEquals(
            MetadataOrigin.AUTHORITATIVE,
            OpdsContributor.publication(source, entry())?.origin,
        )
    }
}
