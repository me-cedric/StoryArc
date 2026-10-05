package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The shelves a reader pins to the home surface.
 *
 * `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the home
 * surface as a shelf of its own, ahead of the unpinned ones", and "unpinning it removes the
 * shelf without altering the collection or the list".
 *
 * The second clause is a promise about something *not* happening, and it is kept by the shape
 * of the type rather than by care: a pin is a key held beside the shelves, so unpinning has
 * nothing to reach into. What is left to assert is the ordering, the round trip through
 * storage, and what happens to a token this version cannot read.
 *
 * Case for case with iOS's `PinnedShelvesTests`, because the stored tokens are the same
 * strings and a reader who moves between the two must not find a pin means something else.
 */
class PinnedShelvesTest {

    private data class Shelf(val name: String, val pin: ShelfPin)

    private fun collection(name: String, id: UUID = UUID.randomUUID()) =
        Shelf(name, ShelfPin.Collection(id))

    private fun list(name: String, id: UUID = UUID.randomUUID()) =
        Shelf(name, ShelfPin.ReadingListPin(id))

    @Test
    fun `a pinned shelf leads the rest`() {
        val shelves = listOf(collection("Image"), list("Crossover"), collection("For bedtime"))
        val pinned = PinnedShelves().toggling(shelves[2].pin)

        assertEquals(
            listOf("For bedtime", "Image", "Crossover"),
            pinned.ordering(shelves) { it.pin }.map { it.name },
        )
    }

    @Test
    fun `pinning moves one shelf and reorders nothing else`() {
        // The reader's own order survives inside each run. A sort would have been shorter and
        // would have reshuffled everything the first time two shelves compared equal.
        val shelves = listOf(collection("A"), list("B"), collection("C"), list("D"))
        val pinned = PinnedShelves().toggling(shelves[3].pin).toggling(shelves[1].pin)

        assertEquals(listOf("B", "D", "A", "C"), pinned.ordering(shelves) { it.pin }.map { it.name })
    }

    @Test
    fun `nothing pinned leaves the list exactly as it was`() {
        val shelves = listOf(collection("A"), list("B"))

        assertEquals(shelves, PinnedShelves().ordering(shelves) { it.pin })
        assertTrue(PinnedShelves().isEmpty)
    }

    @Test
    fun `unpinning is the same action as pinning, and puts the shelf back where it was`() {
        val shelves = listOf(collection("A"), list("B"), collection("C"))
        val once = PinnedShelves().toggling(shelves[2].pin)
        val twice = once.toggling(shelves[2].pin)

        assertTrue(shelves[2].pin in once)
        assertFalse(shelves[2].pin in twice)
        assertEquals(shelves, twice.ordering(shelves) { it.pin })
    }

    @Test
    fun `a collection and a reading list that shared an identifier would not share a pin`() {
        // Not a thing that happens, and exactly the sort of not-a-thing that turns into a bug
        // nobody can reproduce. The two are different types for a reason `Shelves.kt` argues
        // at length; a pin that ignored which was which would quietly undo that.
        val id = UUID.randomUUID()
        val pinned = PinnedShelves().toggling(ShelfPin.Collection(id))

        assertTrue(ShelfPin.Collection(id) in pinned)
        assertFalse(ShelfPin.ReadingListPin(id) in pinned)
    }

    @Test
    fun `a pin survives being written down and read back`() {
        val pinned = PinnedShelves()
            .toggling(ShelfPin.Collection(UUID.randomUUID()))
            .toggling(ShelfPin.ReadingListPin(UUID.randomUUID()))

        assertEquals(pinned, PinnedShelves.of(pinned.tokens))
        // Sorted, so two runs that pinned the same shelves write the same value and a diff of
        // a preferences file is readable.
        assertEquals(pinned.tokens.sorted(), pinned.tokens)
        // The line that asserted `PinnedShelves.STORAGE_KEY` went with the constant: no code
        // on this platform read it, so this test held a spelling nobody wrote. Where the
        // pins actually go is `LibraryPreferences`, and its own tests are what pin that.
    }

    @Test
    fun `the token names the kind in words, so a stored pin is readable and reorder-proof`() {
        // And it is the same string iOS writes, which is the point of asserting the spelling
        // rather than only the round trip.
        val id = UUID.randomUUID()

        assertEquals("collection:$id", ShelfPin.Collection(id).token)
        assertEquals("list:$id", ShelfPin.ReadingListPin(id).token)
    }

    @Test
    fun `a server's shelf is pinned by its triple, and a rename does not unpin it`() {
        // `collections-and-reading-lists`: a server's shelf is "the same kind of object as
        // locally created ones". The triple is RememberedShelf's, without the title, so the
        // server renaming the shelf leaves the pin where the reader put it.
        val source = UUID.randomUUID()
        val shelf = RememberedShelf(RememberedShelfKind.READING_LIST, source, 7, "Crossover")
        val renamed = shelf.copy(title = "Crossovers")
        val pinned = PinnedShelves().toggling(shelf.pin)

        assertTrue(renamed.pin in pinned)
        // Two servers number their reading lists from one, and a collection and a list are
        // numbered apart on each -- so neither the source nor the kind may be dropped.
        assertFalse(ShelfPin.Server(RememberedShelfKind.READING_LIST, UUID.randomUUID(), 7) in pinned)
        assertFalse(ShelfPin.Server(RememberedShelfKind.COLLECTION, source, 7) in pinned)
    }

    @Test
    fun `a server pin survives being written down and read back`() {
        // The same token iOS writes, which is the point of asserting the spelling rather than
        // only the round trip.
        val source = UUID.randomUUID()
        val pin = ShelfPin.Server(RememberedShelfKind.COLLECTION, source, 12)
        val pinned = PinnedShelves().toggling(pin)

        assertEquals("server:collection:$source:12", pin.token)
        assertEquals(pinned, PinnedShelves.of(pinned.tokens))
        assertEquals(
            ShelfPin.Server(RememberedShelfKind.READING_LIST, source, 12),
            ShelfPin.of("server:list:$source:12"),
        )
        assertNull(ShelfPin.of("server:nonsense:$source:12"))
        assertNull(ShelfPin.of("server:list:$source"))
        assertNull(ShelfPin.of("server:list:$source:not-a-number"))
    }

    @Test
    fun `a token this version cannot read is dropped rather than guessed at`() {
        // An unreadable pin drops one shelf off the home surface, which the reader can see and
        // put back. A guessed one pins a shelf they never chose and gives them nothing to undo.
        val good = ShelfPin.Collection(UUID.randomUUID())
        val restored = PinnedShelves.of(
            listOf(good.token, "shelf:not-a-uuid", "list:", "", "nope"),
        )

        assertEquals(listOf(good.token), restored.tokens)
        assertNull(ShelfPin.of("collection:not-a-uuid"))
        assertNull(ShelfPin.of("everything"))
    }
}
