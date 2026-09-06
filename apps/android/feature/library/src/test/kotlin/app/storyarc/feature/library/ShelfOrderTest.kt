package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.model.ShelfEntry
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.KavitaUnsent
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Reordering a server-backed reading list, and what happens to that order when the server is
 * not there.
 *
 * `collections-and-reading-lists` makes the order the meaning of a reading list: "the new
 * order persists and, for a server-backed list, is sent to the server". The same requirement
 * makes an edit to a server list while the server is away "applied locally, marked pending,
 * and pushed on reconnection".
 *
 * The hard claim is the last five tests: a send that fails, and one that lands after a newer
 * order was made, must never cost the reader the order they made. iOS's `ShelfOrderTests`
 * makes the same claims in the same order.
 *
 * Robolectric, because [KavitaProgressStore] is `SharedPreferences` and that needs a context.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShelfOrderTest {

    private val sourceId = "3E7F6C1C-0000-0000-0000-00000000AAAA"
    private val otherSourceId = "3E7F6C1C-0000-0000-0000-00000000BBBB"

    private fun store(): KavitaProgressStore =
        KavitaProgressStore.open(ApplicationProvider.getApplicationContext<Application>())
            .also { it.sent(it.unsent()) }

    private fun origin(chapter: Int = 0) = KavitaOrigin(sourceId, 0, 0, 0, chapter)

    private fun place(item: Int, chapter: Int) = ShelfSync.Place(item, chapter)

    // The moves a new order asks the server for.

    @Test
    fun anOrderThatMatchesTheServerAsksForNoMoves() {
        val places = listOf(place(10, 1), place(11, 2), place(12, 3))
        assertTrue(ShelfSync.moves(places, listOf(1, 2, 3)).isEmpty())
    }

    @Test
    fun anEntryDraggedToTheTopIsMovedFromWhereItIsToWhereItGoes() {
        // Kavita's own `update-position` takes a from and a to, so the plan has to be in
        // positions rather than in identities.
        val places = listOf(place(10, 1), place(11, 2), place(12, 3))
        assertEquals(
            listOf(ShelfSync.Move(item = 12, from = 2, to = 0)),
            ShelfSync.moves(places, listOf(3, 1, 2)),
        )
    }

    @Test
    fun eachMoveIsPlannedAgainstTheOrderTheMovesBeforeItLeftBehind() {
        // The trap this test exists for: planning every move against the *original* order
        // sends positions the server has already invalidated, and the list ends up in an
        // order nobody asked for.
        val places = listOf(place(10, 1), place(11, 2), place(12, 3), place(13, 4))
        val current = mutableListOf(1, 2, 3, 4)
        for (move in ShelfSync.moves(places, listOf(4, 3, 2, 1))) {
            current.add(move.to, current.removeAt(move.from))
        }
        assertEquals(listOf(4, 3, 2, 1), current)
    }

    @Test
    fun anEntryTheServerNoLongerHoldsIsLeftOutOfThePlanRatherThanMoved() {
        val places = listOf(place(10, 1), place(11, 2))
        assertEquals(
            listOf(ShelfSync.Move(item = 11, from = 1, to = 0)),
            ShelfSync.moves(places, listOf(99, 2, 1)),
        )
    }

    // What the reader sees while the order is waiting.

    @Test
    fun theReadersOrderIsDrawnOverTheServersWhileItWaits() {
        val rows = listOf(
            ShelfEntry("1", "One", false),
            ShelfEntry("2", "Two", false),
            ShelfEntry("3", "Three", false),
        )
        assertEquals(
            listOf("3", "1", "2"),
            ShelfSync.arranged(rows, listOf("3", "1", "2")).map { it.id },
        )
    }

    @Test
    fun anEntryTheWantedOrderDoesNotNameKeepsItsPlaceAtTheEnd() {
        // The server may have gained an entry since the reorder was made. Dropping it would
        // be losing a row the reader can see.
        val rows = listOf(
            ShelfEntry("1", "One", false),
            ShelfEntry("2", "Two", false),
            ShelfEntry("9", "Nine", false),
        )
        assertEquals(
            listOf("2", "1", "9"),
            ShelfSync.arranged(rows, listOf("2", "1")).map { it.id },
        )
    }

    @Test
    fun noWantedOrderLeavesTheServersOrderAlone() {
        val rows = listOf(ShelfEntry("1", "One", false), ShelfEntry("2", "Two", false))
        assertEquals(listOf("1", "2"), ShelfSync.arranged(rows, emptyList()).map { it.id })
    }

    // The order the reader made is never lost.

    @Test
    fun aReorderMadeWithNoServerIsWrittenDownRatherThanDropped() = runBlocking {
        val store = store()
        KavitaSync.reorder(store, null, sourceId, listId = 4, order = listOf(3, 1, 2))
        assertEquals(1, store.unsent().size)
        assertEquals(listOf(3, 1, 2), store.unsent().first().order)
        assertEquals(4, store.unsent().first().listId)
    }

    @Test
    fun theLatestOrderWins() {
        val store = store()
        store.hold(KavitaUnsent(origin(), page = 0, listId = 4, order = listOf(1, 2, 3)))
        store.hold(KavitaUnsent(origin(), page = 0, listId = 4, order = listOf(3, 2, 1)))
        assertEquals(1, store.unsent().size)
        assertEquals(listOf(3, 2, 1), store.unsent().first().order)
    }

    @Test
    fun ordersAreHeldPerServer() = runBlocking {
        // Every Kavita numbers its first reading list 1, so two servers holding a list of the
        // same number is the ordinary case rather than the odd one.
        val store = store()
        KavitaSync.reorder(store, null, sourceId, listId = 1, order = listOf(3, 1, 2))
        KavitaSync.reorder(store, null, otherSourceId, listId = 1, order = listOf(9, 8, 7))
        assertEquals(2, store.unsent().size)
        assertEquals(listOf(3, 1, 2), KavitaSync.wantedOrder(store, sourceId, 1))
        assertEquals(listOf(9, 8, 7), KavitaSync.wantedOrder(store, otherSourceId, 1))
    }

    @Test
    fun sentDropsOnlyWhatItSent() {
        // Two moves on a slow server: the first send returns after the second order was
        // written down, and a drop by key would take the reader's newer order with it.
        val store = store()
        val first = KavitaUnsent(origin(), page = 0, listId = 4, order = listOf(1, 2, 3))
        store.hold(first)
        store.hold(KavitaUnsent(origin(), page = 0, listId = 4, order = listOf(3, 2, 1)))
        store.sent(listOf(first))
        assertEquals(1, store.unsent().size)
        assertEquals(listOf(3, 2, 1), store.unsent().first().order)
    }

    @Test
    fun anOrderDoesNotDisplaceAnAppend() {
        val store = store()
        store.hold(KavitaUnsent(origin(chapter = 7), page = 0, listId = 4))
        store.hold(KavitaUnsent(origin(), page = 0, listId = 4, order = listOf(7, 1)))
        assertEquals(2, store.unsent().size)
    }

    @Test
    fun aSendTheServerRefusesNeverLosesTheReadersOrdering() = runBlocking {
        // The data-loss guard, and the reason the order is written down before anything is
        // sent. Port one answers nothing, which is the fastest honest "no server here".
        val store = store()
        val address = KavitaAddress("http://127.0.0.1:1", "k")
        KavitaSync.reorder(store, address, sourceId, listId = 4, order = listOf(3, 1, 2))
        assertEquals(listOf(3, 1, 2), store.unsent().first().order)

        KavitaSync.flush(store, sourceId, address)
        assertEquals(listOf(3, 1, 2), store.unsent().first().order)
    }

    @Test
    fun aHeldOrderIsDurable() {
        // Durability is the whole promise: the reader who reorders on a train has closed the
        // app long before the server is back.
        store().hold(KavitaUnsent(origin(), page = 0, listId = 4, order = listOf(3, 1, 2)))
        val reopened =
            KavitaProgressStore.open(ApplicationProvider.getApplicationContext<Application>())
        assertEquals(listOf(3, 1, 2), reopened.unsent().first().order)
    }
}
