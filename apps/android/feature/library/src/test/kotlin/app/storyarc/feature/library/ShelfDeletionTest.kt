package app.storyarc.feature.library

import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.Shelves
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * What deleting a shelf does, and -- the part the reader is promised -- what it does not.
 *
 * `collections-and-reading-lists`: deleting a collection is confirmed, and the confirmation
 * "states plainly that the publications themselves are not deleted". A dialogue's wording is not
 * testable here; that the wording is *true* is, and it is the half that would rot silently. The
 * other half is the gap itself: a [ShelfDeletion] that exists has changed nothing yet, which is
 * the whole difference from the tap that used to delete outright.
 *
 * iOS's `ShelfDeletionTests` asserts these cases one for one.
 */
class ShelfDeletionTest {

    private fun shelves() = Shelves(
        collections = listOf(
            PublicationCollection(name = "Image Comics", members = setOf("a", "b")),
            PublicationCollection(name = "To read with my kid", members = setOf("b", "c")),
        ),
        lists = listOf(
            ReadingList(name = "Crossover", entries = listOf("a", "c")),
            ReadingList(name = "Recommended path", entries = listOf("b")),
        ),
    )

    @Test
    fun `asking to delete deletes nothing until it is confirmed`() {
        val before = shelves()
        val collection = before.collections.first()
        ShelfDeletion.of(collection)
        assertEquals(2, before.collections.size)
        assertTrue(before.collections.any { it.id == collection.id })
    }

    @Test
    fun `confirming removes that collection and no other shelf`() {
        val before = shelves()
        val after = ShelfDeletion.of(before.collections.first()).apply(before)
        assertEquals(listOf("To read with my kid"), after.collections.map { it.name })
        assertEquals(before.lists.size, after.lists.size)
    }

    @Test
    fun `confirming removes that reading list and leaves the collections alone`() {
        val before = shelves()
        val after = ShelfDeletion.of(before.lists.first()).apply(before)
        assertEquals(listOf("Recommended path"), after.lists.map { it.name })
        assertEquals(before.collections.size, after.collections.size)
    }

    /**
     * The sentence the dialogue says, held up by what a deletion can reach. A shelf holds
     * identities; every other shelf still holds the ones it held, and nothing here can touch the
     * library the identities point into.
     */
    @Test
    fun `the publications stay so another shelf holding the same ones still holds them`() {
        val before = shelves()
        val after = ShelfDeletion.of(before.collections.first()).apply(before)
        assertEquals(setOf("b", "c"), after.collections.first().members)
        assertEquals(listOf("a", "c"), after.lists.first().entries)
    }

    @Test
    fun `a deletion carries the shelf's name so the question can say which one`() {
        val before = shelves()
        val collection = ShelfDeletion.of(before.collections.first())
        val list = ShelfDeletion.of(before.lists.first())

        assertEquals("Image Comics", collection.name)
        assertEquals(ShelfDeletion.Kind.COLLECTION, collection.kind)
        assertEquals("Crossover", list.name)
        assertEquals(ShelfDeletion.Kind.LIST, list.kind)
    }

    /**
     * The kind is what dispatches, not the identity. Shown with the pathological case the two
     * sections make possible in principle: one identity, two shelves, and deleting one of them
     * must not take the other with it.
     */
    @Test
    fun `the kind decides which shelf goes even when an identity is shared`() {
        val id = UUID.randomUUID()
        val collection = PublicationCollection(id = id, name = "Crossover", members = setOf("a"))
        val list = ReadingList(id = id, name = "Crossover", entries = listOf("a"))
        val before = Shelves(collections = listOf(collection), lists = listOf(list))

        assertEquals(1, ShelfDeletion.of(collection).apply(before).lists.size)
        assertTrue(ShelfDeletion.of(collection).apply(before).collections.isEmpty())
        assertEquals(1, ShelfDeletion.of(list).apply(before).collections.size)
        assertTrue(ShelfDeletion.of(list).apply(before).lists.isEmpty())
    }
}
