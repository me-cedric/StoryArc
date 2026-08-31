package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * What the "Downloaded" facet admits, and what keeps it from being the availability axis under
 * a second name.
 *
 * `library-browsing`'s *Filtering offline*: filtering to "Downloaded" shows "only publications
 * readable without a network ... regardless of source state". The clause that is easy to break
 * is the second one — a shelf that hides a downloaded chapter because the Kavita server it came
 * from has gone away is exactly the failure the scenario exists to prevent, and it is invisible
 * until someone is on a plane.
 *
 * iOS's `DownloadFilterTests` asserts these cases one for one.
 */
class DownloadFilterTest {

    private fun publication(name: String, sourceId: UUID? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/fixtures/$name.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = name,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    @Test
    fun `either way keeps a publication whether or not the app fetched it`() {
        assertTrue(DownloadFilter.EITHER.keeps(isDownloaded = true))
        assertTrue(DownloadFilter.EITHER.keeps(isDownloaded = false))
    }

    @Test
    fun `downloaded keeps only what the app fetched and is keeping`() {
        assertTrue(DownloadFilter.DOWNLOADED.keeps(isDownloaded = true))
        assertFalse(DownloadFilter.DOWNLOADED.keeps(isDownloaded = false))
    }

    @Test
    fun `not downloaded is the question before a journey, and keeps the rest`() {
        assertFalse(DownloadFilter.NOT_DOWNLOADED.keeps(isDownloaded = true))
        assertTrue(DownloadFilter.NOT_DOWNLOADED.keeps(isDownloaded = false))
    }

    @Test
    fun `only the two narrowing answers count towards the badge`() {
        assertFalse(DownloadFilter.EITHER.isActive)
        assertTrue(DownloadFilter.DOWNLOADED.isActive)
        assertTrue(DownloadFilter.NOT_DOWNLOADED.isActive)
    }

    @Test
    fun `a downloaded publication survives however its source is doing`() {
        // The whole point of the scenario: a chapter fetched from a server that has since gone
        // away is still readable, so it is still on the shelf. The rule never asks the
        // registry, and this is what says so.
        val fromAwayServer = publication("Nightjar 1", sourceId = UUID.randomUUID())
        val kept = listOf(fromAwayServer).narrowedTo(DownloadFilter.DOWNLOADED) { true }
        assertEquals(listOf("Nightjar 1"), kept.map { it.displayTitle })
    }

    @Test
    fun `a file a folder walk found is on the device and is not downloaded`() {
        // The line the availability axis does not draw. `LibraryAvailability.ON_THIS_DEVICE`
        // keeps this file — it opens with no network — and this group does not, because the app
        // never fetched it and the card it sits on can be pulled.
        val shelf = listOf(publication("Ashfall 1"), publication("Ashfall 2"))
        val isDownloaded = { it: Publication -> it.displayTitle == "Ashfall 2" }

        assertEquals(
            listOf("Ashfall 2"),
            shelf.narrowedTo(DownloadFilter.DOWNLOADED, isDownloaded).map { it.displayTitle },
        )
        assertEquals(
            listOf("Ashfall 1"),
            shelf.narrowedTo(DownloadFilter.NOT_DOWNLOADED, isDownloaded).map { it.displayTitle },
        )
    }

    @Test
    fun `either way hands the shelf back untouched, in the order it arrived`() {
        val shelf = listOf(publication("C"), publication("A"), publication("B"))
        val kept = shelf.narrowedTo(DownloadFilter.EITHER) { false }
        assertEquals(listOf("C", "A", "B"), kept.map { it.displayTitle })
    }

    @Test
    fun `narrowing keeps the order the sort put the shelf in`() {
        // One pass over an already-sorted list. A group that re-sorted would reshuffle the
        // shelf under a reader who only ticked a box.
        val shelf = listOf(publication("C"), publication("A"), publication("B"))
        val kept = shelf.narrowedTo(DownloadFilter.DOWNLOADED) { it.displayTitle != "A" }
        assertEquals(listOf("C", "B"), kept.map { it.displayTitle })
    }

    @Test
    fun `a reader who has never chosen gets the whole shelf`() {
        // A first launch that opened on "Downloaded" would show an empty shelf to a reader who
        // had just added a folder full of comics.
        assertEquals(DownloadFilter.EITHER, DownloadFilter.entries.first())
    }
}
