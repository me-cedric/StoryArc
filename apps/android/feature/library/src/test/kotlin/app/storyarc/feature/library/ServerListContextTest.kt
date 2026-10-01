package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `collections-and-reading-lists` task 7.3: a server reading list never joins the local
 * `Shelves.lists`, so this is what carries "which list, and where in it" from
 * [KavitaListScreen]'s own row tap to the reader's next/previous offer.
 */
class ServerListContextTest {

    @After
    fun clear() {
        ServerListContext.clear()
    }

    private val server = UUID.randomUUID().toString()
    private val address = KavitaAddress("http://localhost:1", "key")

    private fun item(chapterId: Int, order: Int) = KavitaReadingListItem(
        id = chapterId,
        order = order,
        chapterId = chapterId,
        title = "Issue $chapterId",
    )

    private fun publicationOf(chapterId: Int) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(UUID.fromString(server), "chapter:$chapterId"),
        ),
        format = app.storyarc.core.model.PublicationFormat.CBZ,
        displayTitle = "Issue $chapterId",
        origin = app.storyarc.core.model.MetadataOrigin.AUTHORITATIVE,
    )

    private fun place(position: Int) = ServerListContext.Place(
        serverId = server,
        serverAddress = address,
        listId = 8,
        entries = listOf(item(10, 0), item(11, 1), item(12, 2)),
        position = position,
    )

    @Test
    fun `next and previous read the adjacent entries, by position`() {
        val middle = place(1)
        assertEquals(12, middle.next?.chapterId)
        assertEquals(10, middle.previous?.chapterId)
    }

    @Test
    fun `next is null past the last entry, and previous is null before the first`() {
        assertNull(place(2).next)
        assertNull(place(0).previous)
    }

    @Test
    fun `holds is true only for the publication at this place's own position`() {
        val middle = place(1)
        assertEquals(true, middle.holds(publicationOf(11)))
        assertEquals(false, middle.holds(publicationOf(10)))
        assertEquals(false, middle.holds(publicationOf(99)))
    }

    @Test
    fun `holds is false for a publication from a different server`() {
        val middle = place(1)
        val otherServer = publicationOf(11).copy(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(UUID.randomUUID(), "chapter:11"),
            ),
        )
        assertEquals(false, middle.holds(otherServer))
    }

    @Test
    fun `next(after) and previous(before) answer only when current holds that publication`() {
        ServerListContext.opened(place(1))

        assertEquals(12, ServerListContext.next(publicationOf(11))?.identity?.serverIdentifier?.remoteId?.removePrefix("chapter:")?.toInt())
        assertEquals(10, ServerListContext.previous(publicationOf(11))?.identity?.serverIdentifier?.remoteId?.removePrefix("chapter:")?.toInt())

        // A publication this place is not holding gets nothing — the library's own series
        // fallback answers instead, which is `ReaderHost`'s `?:`.
        assertNull(ServerListContext.next(publicationOf(10)))
    }

    @Test
    fun `the placeholder names the entry before it has been fetched`() {
        val named = place(0).placeholder(item(11, 1))
        assertEquals("Issue 11", named.displayTitle)
        assertEquals("chapter:11", named.identity.serverIdentifier?.remoteId)
    }
}
