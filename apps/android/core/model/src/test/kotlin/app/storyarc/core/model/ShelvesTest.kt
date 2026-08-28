package app.storyarc.core.model

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same twelve claims iOS's `ShelvesTests` makes. */
class ShelvesTest {

    private val collectionId = UUID.randomUUID()
    private val listId = UUID.randomUUID()

    private fun shelves() = Shelves()
        .adding(PublicationCollection(id = collectionId, name = "Image Comics"))
        .adding(ReadingList(id = listId, name = "Crossover"))

    @Test
    fun aCollectionHoldsEachPublicationOnceInNoOrder() {
        val shelves = shelves()
            .adding(setOf("a", "b"), collectionId)
            .adding(setOf("b", "c"), collectionId)
        assertEquals(setOf("a", "b", "c"), shelves.collections.first().members)
    }

    @Test
    fun aReadingListKeepsTheOrderEntriesWereAddedIn() {
        val shelves = shelves()
            .appending(listOf("c", "a"), listId)
            .appending(listOf("b", "a"), listId)
        // "a" is not added twice, and "b" lands after it rather than being sorted in.
        assertEquals(listOf("c", "a", "b"), shelves.lists.first().entries)
    }

    @Test
    fun aPublicationCanBeInAnyNumberOfCollections() {
        val second = UUID.randomUUID()
        val shelves = shelves()
            .adding(PublicationCollection(id = second, name = "To read with my kid"))
            .adding(setOf("a"), collectionId)
            .adding(setOf("a"), second)
        assertEquals(2, shelves.collectionsContaining("a").size)
        assertTrue(shelves.collectionsContaining("b").isEmpty())
    }

    @Test
    fun whatComesNextIsTheNextEntryInTheListNotInASeries() {
        val list = shelves().appending(listOf("x", "y", "z"), listId).lists.first()
        assertEquals("y", list.next("x"))
        assertNull(list.next("z"))
        assertNull(list.next("absent"))
    }

    @Test
    fun positionStopsAtTheFirstGap() {
        // A reader who skipped ahead and read entry three has not read one and two.
        val list = shelves().appending(listOf("a", "b", "c", "d"), listId).lists.first()
        assertEquals(1, list.position { it in setOf("a", "c") })
        assertEquals(4, list.position { true })
        assertEquals(0, list.position { false })
    }

    @Test
    fun aDragDownwardsLandsWhereItWasDropped() {
        val shelves = shelves().appending(listOf("a", "b", "c"), listId)
            .moving("a", 2, listId)
        assertEquals(listOf("b", "a", "c"), shelves.lists.first().entries)
    }

    @Test
    fun aDragUpwardsLandsWhereItWasDropped() {
        val shelves = shelves().appending(listOf("a", "b", "c"), listId)
            .moving("c", 0, listId)
        assertEquals(listOf("c", "a", "b"), shelves.lists.first().entries)
    }

    @Test
    fun aCoverTheReaderChoseHasToBeInTheCollection() {
        val shelves = shelves().adding(setOf("a"), collectionId).settingCover("b", collectionId)
        assertNull(shelves.collections.first().coverMemberId)
        assertEquals("a", shelves.settingCover("a", collectionId).collections.first().coverMemberId)
    }

    @Test
    fun removingTheChosenCoversPublicationClearsTheCover() {
        // Left alone it would show a book the collection no longer contains.
        val shelves = shelves()
            .adding(setOf("a", "b"), collectionId)
            .settingCover("a", collectionId)
            .removing(setOf("a"), collectionId)
        assertNull(shelves.collections.first().coverMemberId)
    }

    @Test
    fun aBlankNameIsRefusedRatherThanStored() {
        val shelves = shelves()
            .renamingCollection(collectionId, "   ")
            .renamingList(listId, "")
        assertEquals("Image Comics", shelves.collections.first().name)
        assertEquals("Crossover", shelves.lists.first().name)
    }

    @Test
    fun removingASourceTakesItsGroupingsAndLeavesTheReadersOwn() {
        val source = UUID.randomUUID()
        val shelves = shelves()
            .adding(PublicationCollection(name = "From the server", origin = ShelfOrigin.Server(source)))
            .adding(ReadingList(name = "Server list", origin = ShelfOrigin.Server(source)))
            .removingAll(source)
        assertEquals(listOf("Image Comics"), shelves.collections.map { it.name })
        assertEquals(listOf("Crossover"), shelves.lists.map { it.name })
    }

    @Test
    fun deletingAGroupingLeavesTheOtherKindAlone() {
        val shelves = shelves().deletingCollection(collectionId)
        assertTrue(shelves.collections.isEmpty())
        assertEquals(1, shelves.lists.size)
    }
}
