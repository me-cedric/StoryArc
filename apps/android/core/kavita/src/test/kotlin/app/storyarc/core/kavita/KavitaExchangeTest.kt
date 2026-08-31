package app.storyarc.core.kavita

import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a merge owes a Kavita server, and what a local record may then call synchronised.
 *
 * Mirrors iOS's `KavitaExchangeTests`, assertion for assertion.
 */
class KavitaExchangeTest {

    private fun progress(
        id: String,
        page: Int,
        total: Int = 10,
        finished: Boolean = false,
        synced: Int? = null,
    ) = ReadingProgress(
        identity = PublicationIdentity(contentDigest = id),
        position = ReadingPosition.Page(page, total),
        isFinished = finished,
        updatedAtEpochMillis = 1_700_000_000,
        syncedPosition = synced?.let { ReadingPosition.Page(it, total) },
    )

    private fun chapter(id: Int, pages: Int = 10) =
        KavitaChapter(id = id, number = "1", title = "Chapter $id", pages = pages)

    private fun key(id: String) = PublicationIdentity(contentDigest = id).stableId

    // The arithmetic

    @Test
    fun `a chapter read to its third page is a position on the third page`() {
        assertEquals(ReadingPosition.Page(2, 8), KavitaExchange.position(3, 8))
    }

    @Test
    fun `a chapter nobody has opened is a position at its beginning`() {
        assertEquals(ReadingPosition.Page(0, 8), KavitaExchange.position(0, 8))
    }

    @Test
    fun `a count past the end of the chapter is clamped rather than trusted`() {
        assertEquals(ReadingPosition.Page(7, 8), KavitaExchange.position(99, 8))
    }

    @Test
    fun `a page position is told to the server as its own index`() {
        assertEquals(4, KavitaExchange.pageNumber(ReadingPosition.Page(4, 10), 10))
    }

    @Test
    fun `a reflowable position is told to the server by its fraction`() {
        assertEquals(4, KavitaExchange.pageNumber(ReadingPosition.Reflowable(0.5, "{}"), 9))
    }

    @Test
    fun `a one-page chapter has one answer and no arithmetic`() {
        assertEquals(0, KavitaExchange.pageNumber(ReadingPosition.Page(7, 1), 1))
    }

    @Test
    fun `a page index past the end is clamped rather than sent`() {
        assertEquals(9, KavitaExchange.pageNumber(ReadingPosition.Page(40, 10), 10))
    }

    // The stamp

    @Test
    fun `a record the server has taken is stamped with the position it took`() {
        val stamped = KavitaExchange.settled(progress("one", page = 4))

        assertEquals(ReadingPosition.Page(4, 10), stamped.syncedPosition)
    }

    // The sorting

    @Test
    fun `a server behind the local record is owed that position, at the right page`() {
        val held = progress("one", page = 8, synced = 8)
        val pull = ProgressPull.merging(listOf(progress("one", page = 2))) { held }

        val exchange = KavitaExchange.of(pull, mapOf(key("one") to chapter(41)))

        assertEquals(1, exchange.owed.size)
        assertEquals(41, exchange.owed.first().chapterId)
        assertEquals(8, exchange.owed.first().pageNum)
    }

    @Test
    fun `a position the server has not taken yet is not called synchronised`() {
        val held = progress("one", page = 8, synced = 8)
        val pull = ProgressPull.merging(listOf(progress("one", page = 2))) { held }

        val exchange = KavitaExchange.of(pull, mapOf(key("one") to chapter(41)))

        // The stamp travels with the owed record, to be written once the send lands.
        assertTrue(exchange.toSave.isEmpty())
        assertEquals(ReadingPosition.Page(8, 10), exchange.owed.first().settled.syncedPosition)
    }

    @Test
    fun `a position adopted from the server is written with the stamp on it`() {
        val held = progress("one", page = 2, synced = 2)
        val pull = ProgressPull.merging(listOf(progress("one", page = 6))) { held }

        val exchange = KavitaExchange.of(pull, mapOf(key("one") to chapter(41)))

        assertTrue(exchange.owed.isEmpty())
        assertEquals(ReadingPosition.Page(6, 10), exchange.toSave.first().syncedPosition)
    }

    @Test
    fun `one sweep that finds the server both ahead and behind sorts each apart`() {
        val held = listOf(
            progress("adopt", page = 1, synced = 1),
            progress("push", page = 9, synced = 9),
        )
        val pull = ProgressPull.merging(
            listOf(progress("adopt", page = 5), progress("push", page = 3)),
        ) { wanted -> held.firstOrNull { it.identity.stableId == wanted.stableId } }

        val exchange = KavitaExchange.of(
            pull,
            mapOf(key("adopt") to chapter(41), key("push") to chapter(42)),
        )

        assertEquals(1, exchange.toSave.size)
        assertEquals(ReadingPosition.Page(5, 10), exchange.toSave.first().position)
        assertEquals(listOf(42), exchange.owed.map { it.chapterId })
        assertEquals(9, exchange.owed.first().pageNum)
    }

    @Test
    fun `a conflict the local position wins is written now and owed to the server too`() {
        // Last synced at page 1; this device read on to 7, the server only to 4.
        val held = progress("one", page = 7, synced = 1)
        val pull = ProgressPull.merging(listOf(progress("one", page = 4))) { held }

        val exchange = KavitaExchange.of(pull, mapOf(key("one") to chapter(41)))

        assertEquals(1, pull.conflicts.size)
        // Written as it stands, because the reader's place must survive an unreachable
        // server -- and stamped only by the copy that goes out.
        assertEquals(ReadingPosition.Page(1, 10), exchange.toSave.first().syncedPosition)
        assertEquals(7, exchange.owed.first().pageNum)
    }

    @Test
    fun `a conflict the server wins is adopted and owed nothing`() {
        val held = progress("one", page = 3, synced = 1)
        val pull = ProgressPull.merging(listOf(progress("one", page = 8))) { held }

        val exchange = KavitaExchange.of(pull, mapOf(key("one") to chapter(41)))

        assertEquals(1, pull.conflicts.size)
        assertTrue(exchange.owed.isEmpty())
        assertEquals(ReadingPosition.Page(8, 10), exchange.toSave.first().syncedPosition)
    }

    @Test
    fun `a record with no chapter behind it is left out rather than guessed at`() {
        val held = progress("one", page = 8, synced = 8)
        val pull = ProgressPull.merging(listOf(progress("one", page = 2))) { held }

        assertTrue(KavitaExchange.of(pull, emptyMap()).owed.isEmpty())
    }

    @Test
    fun `a chapter the server reports no pages for is owed nothing`() {
        val held = progress("one", page = 8, synced = 8)
        val pull = ProgressPull.merging(listOf(progress("one", page = 2))) { held }

        val exchange = KavitaExchange.of(pull, mapOf(key("one") to chapter(41, pages = 0)))

        assertTrue(exchange.owed.isEmpty())
    }

    @Test
    fun `nothing merged is nothing to write and nothing to send`() {
        val exchange = KavitaExchange.of(ProgressPull(), emptyMap())

        assertTrue(exchange.toSave.isEmpty() && exchange.owed.isEmpty())
        assertNull(exchange.owed.firstOrNull())
    }
}
