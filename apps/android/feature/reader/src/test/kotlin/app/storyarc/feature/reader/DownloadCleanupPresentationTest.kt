package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What the end screen shows about a publication's download (D7). iOS's
 * `DownloadCleanupPresentationTests` asserts the same table.
 */
class DownloadCleanupPresentationTest {

    @Test
    fun `no offer at all is nothing shown - most publications were never a download`() {
        assertEquals(DownloadCleanupPresentation.NONE, DownloadCleanupPresentation.resolved(null))
    }

    @Test
    fun `a download that stays gets the offer to remove it`() {
        val offer = DownloadCleanupOffer(isRemovedOnClose = { false }, onRemove = {}, onKeep = {})
        assertEquals(DownloadCleanupPresentation.OFFER_REMOVAL, DownloadCleanupPresentation.resolved(offer))
    }

    @Test
    fun `a download that goes on close says so, and offers to keep it`() {
        val offer = DownloadCleanupOffer(isRemovedOnClose = { true }, onRemove = {}, onKeep = {})
        assertEquals(
            DownloadCleanupPresentation.STATE_AND_OFFER_KEEP,
            DownloadCleanupPresentation.resolved(offer),
        )
    }

    @Test
    fun `after Keep, the screen stops saying the download goes`() {
        // Before, the sentence and the Keep button stayed up after the tap, and the
        // sentence was then false.
        val offer = DownloadCleanupOffer(isRemovedOnClose = { true }, onRemove = {}, onKeep = {})
        assertEquals(
            DownloadCleanupPresentation.OFFER_REMOVAL,
            DownloadCleanupPresentation.resolved(offer, choice = false),
        )
    }

    @Test
    fun `after Remove download, the screen says it goes on close, and offers Keep`() {
        val offer = DownloadCleanupOffer(isRemovedOnClose = { false }, onRemove = {}, onKeep = {})
        assertEquals(
            DownloadCleanupPresentation.STATE_AND_OFFER_KEEP,
            DownloadCleanupPresentation.resolved(offer, choice = true),
        )
    }
}
