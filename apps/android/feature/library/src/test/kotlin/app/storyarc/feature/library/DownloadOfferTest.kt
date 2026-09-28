package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.StreamingCapability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one action list a publication offers, wherever it is drawn -- the piece this menu
 * decides for itself: whether there is anything to download or to remove. iOS's
 * `PublicationActionMenuTests` asks the same three questions of the same rule.
 */
class DownloadOfferTest {

    private fun publication(
        format: PublicationFormat = PublicationFormat.CBZ,
        streaming: StreamingCapability = StreamingCapability.STREAMS,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/one.${format.name.lowercase()}"),
        format = format,
        displayTitle = "One",
        origin = MetadataOrigin.INFERRED,
        streaming = streaming,
    )

    @Test
    fun `a publication no decoder will open cannot be downloaded`() {
        val refused = publication(format = PublicationFormat.CB7, streaming = StreamingCapability.REFUSED)
        assertFalse(refused.isOpenable)
        assertFalse(PublicationActions.canDownload(refused))
    }

    @Test
    fun `a folder of images has nothing a single file could copy`() {
        assertFalse(PublicationActions.canDownload(publication(format = PublicationFormat.IMAGE_FOLDER)))
    }

    @Test
    fun `an ordinary openable publication can be downloaded`() {
        assertTrue(PublicationActions.canDownload(publication(format = PublicationFormat.CBZ)))
    }

    @Test
    fun `a kept copy offers to remove itself, whatever else is true of it`() {
        assertEquals(
            DownloadOffer.Remove,
            DownloadOffer.of(publication(format = PublicationFormat.IMAGE_FOLDER), isKept = true, isLocalFile = true),
        )
        assertEquals(
            DownloadOffer.Remove,
            DownloadOffer.of(
                publication(format = PublicationFormat.CB7, streaming = StreamingCapability.REFUSED),
                isKept = true,
                isLocalFile = false,
            ),
        )
    }

    @Test
    fun `a copy that could be fetched and is not kept offers to download`() {
        assertEquals(
            DownloadOffer.Download,
            DownloadOffer.of(publication(format = PublicationFormat.CBZ), isKept = false, isLocalFile = true),
        )
    }

    @Test
    fun `nothing that could be fetched offers neither`() {
        assertEquals(
            DownloadOffer.None,
            DownloadOffer.of(publication(format = PublicationFormat.IMAGE_FOLDER), isKept = false, isLocalFile = true),
        )
        assertEquals(
            DownloadOffer.None,
            DownloadOffer.of(
                publication(format = PublicationFormat.CB7, streaming = StreamingCapability.REFUSED),
                isKept = false,
                isLocalFile = true,
            ),
        )
    }

    @Test
    fun `a row whose bytes are on a server offers no download the menu cannot deliver`() {
        // The menu copies a file that is already on this device. A Kavita, OPDS or share
        // row has no such file, so a Download row there would change nothing.
        assertEquals(
            DownloadOffer.None,
            DownloadOffer.of(publication(format = PublicationFormat.CBZ), isKept = false, isLocalFile = false),
        )
    }
}
