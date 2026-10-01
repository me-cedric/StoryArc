package app.storyarc.core.persistence

import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin
import app.storyarc.core.model.Shelves
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Collections and reading lists, read back from disk.
 *
 * iOS's `ShelvesStoreTests` makes the same four claims. Task 7.13 adds the fourth: a reading
 * list's own chosen cover has to survive the round trip the same way a collection's already
 * does.
 */
class ShelvesStoreTest {

    private fun store() = ShelvesStore(FakePreferences())

    @Test
    fun `an empty store has nothing on its shelves`() {
        assertEquals(Shelves(), store().shelves())
    }

    @Test
    fun `a collection and a list survive the round trip`() {
        val store = store()
        val collectionId = UUID.randomUUID()
        val listId = UUID.randomUUID()
        store.save(
            Shelves()
                .adding(PublicationCollection(id = collectionId, name = "Image Comics"))
                .adding(ReadingList(id = listId, name = "Crossover"))
                .adding(setOf("a", "b"), to = collectionId)
                .settingCover("a", on = collectionId)
                .appending(listOf("c", "a", "b"), to = listId)
                // Task 7.13: a list's own chosen cover, the same round trip a collection's
                // already makes.
                .settingListCover("a", onList = listId),
        )

        val read = store.shelves()
        assertEquals(setOf("a", "b"), read.collections.first().members)
        assertEquals("a", read.collections.first().coverMemberId)
        // The order is the point of a list, and it has to survive being written down.
        assertEquals(listOf("c", "a", "b"), read.lists.first().entries)
        assertEquals("a", read.lists.first().coverMemberId)
    }

    @Test
    fun `a server's groupings are not written`() {
        // They belong to the server and are fetched. A cached copy that outlived a server
        // edit is the stale claim the conflict rule exists to prevent.
        val store = store()
        store.save(
            Shelves()
                .adding(PublicationCollection(name = "Local", origin = ShelfOrigin.Local))
                .adding(
                    PublicationCollection(
                        name = "Remote",
                        origin = ShelfOrigin.Server(UUID.randomUUID()),
                    ),
                ),
        )
        assertEquals(listOf("Local"), store.shelves().collections.map { it.name })
    }

    @Test
    fun `a list with no chosen cover reads back with none`() {
        val store = store()
        val listId = UUID.randomUUID()
        store.save(Shelves().adding(ReadingList(id = listId, name = "Crossover")))

        assertNull(store.shelves().lists.first().coverMemberId)
    }
}
