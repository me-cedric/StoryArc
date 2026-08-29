package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same seven claims iOS's `BulkSelectionTests` makes. */
class BulkSelectionTest {

    private val order = listOf("a", "b", "c", "d")

    private fun collection(members: Set<String>) =
        PublicationCollection(name = "Image Comics", members = members)

    @Test
    fun addingASelectionToACollectionTouchesEveryMemberOfIt() {
        val joining = BulkSelection.joining(setOf("a", "b", "c"), collection(emptySet()))
        assertEquals(setOf("a", "b", "c"), joining)
    }

    @Test
    fun aSelectionOfOneIsABulkActionLikeAnyOther() {
        assertEquals(setOf("a"), BulkSelection.joining(setOf("a"), collection(emptySet())))
        assertEquals(
            listOf("a"),
            BulkSelection.appending(setOf("a"), ReadingList(name = "Crossover"), order),
        )
        assertEquals(setOf("a"), BulkSelection.marking(setOf("a"), true, emptySet()))
        assertEquals(setOf("a"), BulkSelection.downloading(setOf("a"), emptySet()))
    }

    @Test
    fun theEmptySelectionDoesNothingAtAll() {
        assertTrue(BulkSelection.joining(emptySet(), collection(setOf("a"))).isEmpty())
        assertTrue(
            BulkSelection.appending(emptySet(), ReadingList(name = "Crossover"), order).isEmpty(),
        )
        assertTrue(BulkSelection.marking(emptySet(), true, setOf("a")).isEmpty())
        assertTrue(BulkSelection.downloading(emptySet(), setOf("a")).isEmpty())
    }

    // What the undo has to put back is what the action moved, and nothing else.
    @Test
    fun aMemberTheCollectionAlreadyHoldsIsNotPartOfWhatTheActionChanged() {
        assertEquals(setOf("b"), BulkSelection.joining(setOf("a", "b"), collection(setOf("a"))))
    }

    @Test
    fun entriesReachAReadingListInTheOrderTheLibraryWasShowingThem() {
        val list = ReadingList(name = "Crossover", entries = listOf("c"))
        assertEquals(
            listOf("a", "d"),
            BulkSelection.appending(setOf("d", "a", "c"), list, order),
        )
    }

    @Test
    fun markingReadChangesOnlyWhatWasUnreadAndUnreadOnlyWhatWasFinished() {
        assertEquals(setOf("b"), BulkSelection.marking(setOf("a", "b"), true, setOf("a")))
        assertEquals(setOf("a"), BulkSelection.marking(setOf("a", "b"), false, setOf("a")))
    }

    @Test
    fun aPublicationAlreadyOnTheDeviceIsNotFetchedASecondTime() {
        assertEquals(setOf("b"), BulkSelection.downloading(setOf("a", "b"), setOf("a")))
        assertTrue(BulkSelection.downloading(setOf("a"), setOf("a")).isEmpty())
    }
}
