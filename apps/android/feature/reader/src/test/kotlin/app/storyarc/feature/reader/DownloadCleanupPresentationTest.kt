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
    fun `with the sweep off, the end screen offers to remove the download`() {
        val offer = DownloadCleanupOffer(automaticCleanupIsOn = false, onRemove = {}, onKeep = {})
        assertEquals(DownloadCleanupPresentation.OFFER_REMOVAL, DownloadCleanupPresentation.resolved(offer))
    }

    @Test
    fun `with the sweep on, the end screen states it and offers to keep this one`() {
        val offer = DownloadCleanupOffer(automaticCleanupIsOn = true, onRemove = {}, onKeep = {})
        assertEquals(
            DownloadCleanupPresentation.STATE_AND_OFFER_KEEP,
            DownloadCleanupPresentation.resolved(offer),
        )
    }
}
