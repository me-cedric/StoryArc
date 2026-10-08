package app.storyarc.core.model

import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` tasks 3.3 and 3.4: shelves merge their members, and a deletion travels. iOS's
 * `ShelfSyncTests` makes the same claims.
 */
class ShelfSyncTest {

    private val shelf = UUID.fromString("cccccccc-0000-0000-0000-000000000003")
    private val list = UUID.fromString("dddddddd-0000-0000-0000-000000000004")

    private fun shared(): LibrarySnapshot = LibrarySnapshot(
        shelves = Shelves(
            collections = listOf(PublicationCollection(id = shelf, name = "Image", members = setOf("a"), changedAtEpochMillis = moment(1))),
            lists = listOf(ReadingList(id = list, name = "Crossover", entries = listOf("a"), changedAtEpochMillis = moment(1))),
        ),
    )

    /** The reader's own change on a device, stamped as the store stamps it. */
    private fun SyncDevice.change(at: Long, edit: (Shelves) -> Shelves) {
        val stamped = ShelfStamps.stamped(library.shelves, library.removedShelves, edit(library.shelves), library.removedShelves, at)
        library = library.copy(shelves = stamped.shelves, removedShelves = stamped.removed)
    }

    @Test
    fun `members two devices added to one shelf both arrive`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", shared())
        val b = SyncDevice("device-b", shared())
        a.change(moment(2)) { it.adding(setOf("from-a"), to = shelf) }
        b.change(moment(3)) { it.adding(setOf("from-b"), to = shelf) }

        a.sync(place, moment(4))
        b.sync(place, moment(5))
        a.sync(place, moment(6))

        for (device in listOf(a, b)) {
            assertEquals(setOf("a", "from-a", "from-b"), device.library.shelves.collections.single().members)
        }
    }

    @Test
    fun `a reading list keeps the older side's order first`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", shared())
        val b = SyncDevice("device-b", shared())
        a.change(moment(2)) { it.appending(listOf("a2", "a3"), to = list) }
        b.change(moment(3)) { it.appending(listOf("b2"), to = list) }

        a.sync(place, moment(4))
        b.sync(place, moment(5))
        a.sync(place, moment(6))

        val expected = listOf("a", "a2", "a3", "b2")
        assertEquals(expected, a.library.shelves.lists.single().entries)
        assertEquals(expected, b.library.shelves.lists.single().entries)
    }

    @Test
    fun `the name changed last wins`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", shared())
        val b = SyncDevice("device-b", shared())
        a.change(moment(3)) { it.renamingCollection(shelf, "Image Comics") }
        b.change(moment(2)) { it.renamingCollection(shelf, "Older name") }

        a.sync(place, moment(4))
        b.sync(place, moment(5))

        assertEquals("Image Comics", b.library.shelves.collections.single().name)
    }

    @Test
    fun `a shelf deleted on one device is gone on the other and stays gone`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", shared())
        val b = SyncDevice("device-b", shared())
        a.sync(place, moment(2))
        b.sync(place, moment(3))

        a.change(moment(4)) { it.deletingCollection(shelf).deletingList(list) }
        a.sync(place, moment(5))
        b.sync(place, moment(6))
        a.sync(place, moment(7))
        b.sync(place, moment(8))

        for (device in listOf(a, b)) {
            assertTrue(device.library.shelves.collections.isEmpty())
            assertTrue(device.library.shelves.lists.isEmpty())
        }
        assertEquals(setOf(shelf.toString(), list.toString()), place.document().library.removedShelves.map { it.id }.toSet())
        assertEquals("device-a", place.document().library.removedShelves.first().removedBy)
    }

    @Test
    fun `a shelf changed after the deletion comes back`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", shared())
        val b = SyncDevice("device-b", shared())
        a.change(moment(4)) { it.deletingCollection(shelf) }
        b.change(moment(6)) { it.adding(setOf("later"), to = shelf) }

        a.sync(place, moment(7))
        b.sync(place, moment(8))
        a.sync(place, moment(9))

        assertEquals(setOf("a", "later"), a.library.shelves.collections.single().members)
        assertTrue(a.library.removedShelves.none { it.id == shelf })
    }

    @Test
    fun `a store records a deletion and stamps a change`() {
        val before = shared().shelves
        val after = before.deletingList(list).renamingCollection(shelf, "Renamed")

        val stamped = ShelfStamps.stamped(before, emptyList(), after, emptyList(), moment(9))

        assertEquals(listOf(ShelfTombstone(list, moment(9))), stamped.removed)
        assertEquals(moment(9), stamped.shelves.collections.single().changedAtEpochMillis)
    }

    @Test
    fun `a moment a merge brought is kept, and a shelf put back loses its tombstone`() {
        val before = shared().shelves
        val merged = before.copy(collections = before.collections.map { it.copy(name = "From B", changedAtEpochMillis = moment(5)) })
        val kept = ShelfStamps.stamped(before, emptyList(), merged, emptyList(), moment(9))
        assertEquals(moment(5), kept.shelves.collections.single().changedAtEpochMillis)

        val gone = ShelfStamps.stamped(before, emptyList(), before.deletingCollection(shelf), emptyList(), moment(10))
        val back = ShelfStamps.stamped(gone.shelves, gone.removed, before, gone.removed, moment(11))
        assertEquals(moment(11), back.shelves.collections.single().changedAtEpochMillis)
        assertTrue(back.removed.none { it.id == shelf })
    }
}
