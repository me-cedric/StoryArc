package app.storyarc.feature.library

import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which copy a library row asks for when the reader presses the page's primary action.
 *
 * `publication-detail` requires that "the primary action is never one that fails when it is
 * taken", and a download that arrives in a format the row does not describe is a slower way
 * of failing: the page names PDF, the reader gets a CBZ, and the cover fit, the format row and
 * the reading direction now all describe a file nobody has.
 *
 * Pure on purpose. The decision needs no Context, no queue and no network, so it is tested
 * without them.
 */
class PublicationCopyTest {

    private val source = UUID.randomUUID()

    private val epub = "application/epub+zip"
    private val pdf = "application/pdf"
    private val cbz = "application/vnd.comicbook+zip"

    private fun row(format: PublicationFormat) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = source,
                remoteId = "opds:urn:uuid:1",
            ),
        ),
        format = format,
        displayTitle = "Tidal Reach",
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = source,
    )

    private fun link(
        type: String,
        kind: OpdsAcquisition.Kind = OpdsAcquisition.Kind.OPEN,
    ) = OpdsAcquisition(href = "https://example/get?type=$type", mediaType = type, kind = kind)

    private fun entry(vararg links: OpdsAcquisition) = OpdsEntry(
        id = "urn:uuid:1",
        title = "Tidal Reach",
        acquisitions = links.toList(),
    )

    @Test
    fun `the copy taken is the format the row was filed under`() {
        // The row was filed as PDF because the feed declared PDF first, which is how
        // `OpdsContributor.publication` reads an entry.
        val offered = entry(link(pdf), link(cbz))

        assertEquals(pdf, acquisitionFor(row(PublicationFormat.PDF), offered)?.mediaType)
        // And this is why the decision is not `best`: the app's own ranking prefers the comic
        // container, so `best` would fetch a file the row does not describe.
        assertEquals(cbz, CatalogueAcquisition.best(offered)?.mediaType)
    }

    @Test
    fun `a format the entry no longer offers falls back to the best it does`() {
        val offered = entry(link(cbz))

        assertEquals(cbz, acquisitionFor(row(PublicationFormat.EPUB), offered)?.mediaType)
    }

    @Test
    fun `an entry that can only be borrowed offers no copy`() {
        val offered = entry(link(epub, OpdsAcquisition.Kind.BORROW))

        assertNull(acquisitionFor(row(PublicationFormat.EPUB), offered))
    }
}
