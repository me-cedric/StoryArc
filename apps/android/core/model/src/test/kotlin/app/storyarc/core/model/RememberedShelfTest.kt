package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

/**
 * A shelf a server told the app about, written down.
 *
 * The token is the whole contract: the home surface reads it back after the process that
 * wrote it has gone, so a token that parses differently from the way it was written loses a
 * shelf silently. Case for case with iOS's `RememberedShelfTests`, because both platforms
 * write the same strings.
 */
class RememberedShelfTest {

    private val source: UUID = UUID.fromString("6f1a4a8e-0000-4000-8000-000000000001")

    private fun shelf(
        kind: RememberedShelfKind = RememberedShelfKind.COLLECTION,
        serverId: Int = 7,
        title: String = "Image Comics",
    ) = RememberedShelf(kind, source, serverId, title)

    @Test
    fun `a collection round-trips`() {
        val shelf = shelf()
        assertEquals(shelf, RememberedShelf.of(shelf.token))
    }

    @Test
    fun `a reading list round-trips and is not read back as a collection`() {
        val shelf = shelf(kind = RememberedShelfKind.READING_LIST, title = "Crisis, in order")
        val read = RememberedShelf.of(shelf.token)
        assertEquals(shelf, read)
        assertEquals(RememberedShelfKind.READING_LIST, read?.kind)
    }

    @Test
    fun `the two kinds are written down with the words the pins already use`() {
        assertEquals("collection", shelf().token.substringBefore(':'))
        assertEquals("list", shelf(kind = RememberedShelfKind.READING_LIST).token.substringBefore(':'))
    }

    @Test
    fun `a title holding a colon survives`() {
        val shelf = shelf(title = "Batman: Year One")
        assertEquals("Batman: Year One", RememberedShelf.of(shelf.token)?.title)
    }

    @Test
    fun `a title holding spaces survives`() {
        val shelf = shelf(title = "To read with my kid")
        assertEquals(shelf, RememberedShelf.of(shelf.token))
    }

    @Test
    fun `a token this version cannot read is dropped rather than guessed`() {
        assertNull(RememberedShelf.of("shelf:$source:7:Something"))
        assertNull(RememberedShelf.of("collection:not-a-uuid:7:Something"))
        assertNull(RememberedShelf.of("collection:$source:seven:Something"))
        assertNull(RememberedShelf.of("collection:$source:7:"))
        assertNull(RememberedShelf.of("collection:$source:7"))
        assertNull(RememberedShelf.of(""))
    }

    @Test
    fun `a record drops only the tokens it cannot read`() {
        val kept = shelf(title = "Kept")
        val read = RememberedShelf.of(listOf(kept.token, "nonsense", "collection:x:1:No"))
        assertEquals(listOf(kept), read)
    }

    @Test
    fun `what is written down is sorted, so two fetches of one set write one value`() {
        val a = shelf(serverId = 1, title = "Alpha")
        val b = shelf(serverId = 2, title = "Beta")
        assertEquals(
            RememberedShelf.tokens(listOf(a, b)),
            RememberedShelf.tokens(listOf(b, a)),
        )
    }

    @Test
    fun `every shelf written survives the trip back`() {
        val shelves = listOf(
            shelf(serverId = 1, title = "Alpha"),
            shelf(kind = RememberedShelfKind.READING_LIST, serverId = 2, title = "Beta: part two"),
        )
        assertEquals(
            shelves.sortedBy { it.token },
            RememberedShelf.of(RememberedShelf.tokens(shelves)).sortedBy { it.token },
        )
    }
}
