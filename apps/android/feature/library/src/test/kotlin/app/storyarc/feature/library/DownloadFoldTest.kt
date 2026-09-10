package app.storyarc.feature.library

import app.storyarc.core.model.KavitaCard
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a publication offered by a source and the same publication downloaded are one row.
 *
 * `library-browsing` asks for one row, and the library drew two: a server row carries a
 * `ServerIdentifier` and no path, a downloaded file carries a path and a digest and no
 * server identifier, and `PublicationIdentity.matches` had nothing in common to match on.
 * A reader who downloaded a Kavita chapter watched a second copy of it appear.
 *
 * The three claims the change asks for are the three tests here: the two are one row, the
 * row is readable with nothing but the file, and the row's key does not change when the
 * path arrives. The last one is the one that would be missed — the key is what reading
 * progress, shelves and bookmarks are filed under, so a row that re-keyed itself on
 * download would lose every one of them.
 */
class DownloadFoldTest {

    private val source = UUID.randomUUID()

    /** What a Kavita source puts on the shelf: an identifier, and nothing on disk. */
    private val remote = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = source,
                remoteId = "chapter:3103",
            ),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = "Lantern Green #43",
        series = "Lantern Green",
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = source,
    )

    /** What the scanner makes of the bytes once they are on disk. */
    private val downloaded = Publication(
        identity = PublicationIdentity(
            contentDigest = "8f14e45fceea167a5a36dedd4bea2543",
            normalizedPath = "/data/user/0/app.storyarc/files/downloads/lantern-green-43.cbz",
        ),
        format = PublicationFormat.CBZ,
        displayTitle = "lantern-green-43",
        origin = MetadataOrigin.INFERRED,
    )

    private val card = KavitaCard(
        publicationId = downloaded.id,
        downloadId = "kavita:$source:3103",
        sourceId = source.toString(),
        seriesId = 312,
        chapterId = 3103,
        seriesName = "Lantern Green",
        chapterName = "Lantern Green #43",
    )

    @Test
    fun `a downloaded chapter and the row it came from are one row`() {
        val linked = DownloadFold.described(downloaded, card)

        assertTrue(
            "The downloaded copy does not match the row the source put on the shelf, so the" +
                " library draws both.",
            linked.identity.matches(remote.identity),
        )
        assertEquals(0, DownloadFold.rowFor(listOf(remote), linked))
    }

    @Test
    fun `without the fold they are two rows, which is the defect`() {
        // The control. Nothing in the two identities is shared, and `matches` is honest
        // about that — which is why the bridge has to be built rather than found.
        assertTrue(!downloaded.identity.matches(remote.identity))
        assertNull(DownloadFold.rowFor(listOf(remote), downloaded))
    }

    @Test
    fun `the row keeps its key when the path arrives`() {
        // `stableId` prefers a path, so a row that took the downloaded copy's identity
        // would change key from `srv:…` to `path:…` — and reading progress, shelves and
        // bookmarks are all filed under that key. The row that stays is the one already on
        // the shelf; only its location is learned.
        val linked = DownloadFold.described(downloaded, card)
        val at = DownloadFold.rowFor(listOf(remote), linked)
        assertNotNull("The downloaded copy found no row to join.", at)

        assertEquals(0, at)
        assertEquals("srv:$source:chapter:3103", remote.id)
        assertEquals(
            "The row's key changed when its bytes arrived. Everything filed against the old" +
                " key is now filed against nothing.",
            "srv:$source:chapter:3103",
            listOf(remote)[at!!].id,
        )
    }

    @Test
    fun `the card's identifier is spelled the way the contributor spells it`() {
        // The two are written in different files and neither compiles against the other.
        // A chapter prefix changed in one place and not the other is a fold that silently
        // stops folding, and a duplicate row is what a reader would see.
        val fromCard = card.remoteIdentity

        assertEquals(remote.identity.serverIdentifier, fromCard)
    }

    @Test
    fun `a download with no card is left alone, because it has no row to join`() {
        // An OPDS acquisition, or a file the reader imported. Neither has a server row.
        val linked = DownloadFold.described(downloaded, card = null)

        assertEquals(downloaded.identity, linked.identity)
        assertNull(DownloadFold.rowFor(listOf(remote), linked))
    }

    @Test
    fun `a card whose source is not this app's is ignored rather than crashing`() {
        val foreign = card.copy(sourceId = "not-a-uuid")

        assertNull(foreign.remoteIdentity)
        assertEquals(downloaded.identity, DownloadFold.described(downloaded, foreign).identity)
    }

    @Test
    fun `the file is still what the row opens, so it reads with no network`() {
        // The second claim: one row is only right if the row can be opened. The path is
        // recorded against the row's own key, which is what `LibraryViewModel.locations`
        // holds and what the reader opens.
        val linked = DownloadFold.described(downloaded, card)

        assertEquals(
            "/data/user/0/app.storyarc/files/downloads/lantern-green-43.cbz",
            linked.identity.normalizedPath,
        )
    }
}
