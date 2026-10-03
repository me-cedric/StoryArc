package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one action list every surface draws, in the order `library-browsing`'s *A publication's
 * actions wherever it is drawn* names them. [PublicationActionMenu] (the composable) asks
 * this same function for its own order and gating, so a test here is a test of what a reader
 * actually sees on a long press.
 */
class PublicationActionMenuItemsTest {

    @Test
    fun `the plain case offers open, mark, add to shelf and show details, and nothing else`() {
        assertEquals(
            listOf(
                PublicationMenuAction.OPEN,
                PublicationMenuAction.MARK,
                PublicationMenuAction.ADD_TO_SHELF,
                PublicationMenuAction.SHOW_DETAILS,
            ),
            PublicationActionMenuItems.of(
                offersRestart = false,
                downloadOffer = DownloadOffer.None,
                offersRemoveFromShelf = false,
            ),
        )
    }

    @Test
    fun `restart sits right after mark, and only when offered`() {
        val items = PublicationActionMenuItems.of(
            offersRestart = true,
            downloadOffer = DownloadOffer.None,
            offersRemoveFromShelf = false,
        )
        assertEquals(
            listOf(PublicationMenuAction.MARK, PublicationMenuAction.RESTART),
            items.filter { it == PublicationMenuAction.MARK || it == PublicationMenuAction.RESTART },
        )
        assertFalse(
            PublicationMenuAction.RESTART in PublicationActionMenuItems.of(
                offersRestart = false,
                downloadOffer = DownloadOffer.None,
                offersRemoveFromShelf = false,
            ),
        )
    }

    @Test
    fun `download and remove download are mutually exclusive, and absent means neither`() {
        assertTrue(
            PublicationMenuAction.DOWNLOAD in PublicationActionMenuItems.of(
                offersRestart = false,
                downloadOffer = DownloadOffer.Download,
                offersRemoveFromShelf = false,
            ),
        )
        assertTrue(
            PublicationMenuAction.REMOVE_DOWNLOAD in PublicationActionMenuItems.of(
                offersRestart = false,
                downloadOffer = DownloadOffer.Remove,
                offersRemoveFromShelf = false,
            ),
        )
        val neither = PublicationActionMenuItems.of(
            offersRestart = false,
            downloadOffer = DownloadOffer.None,
            offersRemoveFromShelf = false,
        )
        assertFalse(PublicationMenuAction.DOWNLOAD in neither)
        assertFalse(PublicationMenuAction.REMOVE_DOWNLOAD in neither)
    }

    @Test
    fun `remove from shelf is offered only where there is one, and sits before show details`() {
        val onAShelf = PublicationActionMenuItems.of(
            offersRestart = false,
            downloadOffer = DownloadOffer.None,
            offersRemoveFromShelf = true,
        )
        assertEquals(
            listOf(PublicationMenuAction.REMOVE_FROM_SHELF, PublicationMenuAction.SHOW_DETAILS),
            onAShelf.takeLast(2),
        )
        assertFalse(
            PublicationMenuAction.REMOVE_FROM_SHELF in PublicationActionMenuItems.of(
                offersRestart = false,
                downloadOffer = DownloadOffer.None,
                offersRemoveFromShelf = false,
            ),
        )
    }

    @Test
    fun `open is always first and show details is always last`() {
        val items = PublicationActionMenuItems.of(
            offersRestart = true,
            downloadOffer = DownloadOffer.Download,
            offersRemoveFromShelf = true,
        )
        assertEquals(PublicationMenuAction.OPEN, items.first())
        assertEquals(PublicationMenuAction.SHOW_DETAILS, items.last())
    }
}
