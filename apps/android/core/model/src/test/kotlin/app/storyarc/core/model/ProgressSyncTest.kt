package app.storyarc.core.model

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` tasks 3.2 and 5.1: reading progress through the sync document, by ADR-0006,
 * between two devices that share one place. iOS's `ProgressSyncTests` makes the same claims.
 */
class ProgressSyncTest {

    private val book = PublicationIdentity(contentDigest = "d1")

    @Test
    fun `a sync stamps the position the document now holds`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        a.read(book, page = 40, at = moment(1))

        a.sync(place, moment(2))

        assertEquals(ReadingPosition.Page(40, 100), a.position(book)?.syncedPosition)
    }

    @Test
    fun `after a sync, a further move on the other device arrives with no conflict`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        val b = SyncDevice("device-b")
        a.read(book, page = 10, at = moment(1))
        a.sync(place, moment(2))
        b.sync(place, moment(3))
        // A reads on, and the watermark of the first sync is now behind it.
        a.read(book, page = 40, at = moment(4))
        a.sync(place, moment(5))
        b.sync(place, moment(6))
        b.read(book, page = 60, at = moment(7))
        b.sync(place, moment(8))

        a.sync(place, moment(9))

        assertEquals(ReadingPosition.Page(60, 100), a.position(book)?.position)
        assertEquals(emptyList<ProgressPull.Conflict>(), a.conflicts + b.conflicts)
    }

    @Test
    fun `two devices that never synced settle on the further position with no notice`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        val b = SyncDevice("device-b")
        a.read(book, page = 40, at = moment(1))
        b.read(book, page = 20, at = moment(2))

        a.sync(place, moment(3))
        b.sync(place, moment(4))
        a.sync(place, moment(5))

        assertEquals(ReadingPosition.Page(40, 100), a.position(book)?.position)
        assertEquals(ReadingPosition.Page(40, 100), b.position(book)?.position)
        assertEquals(emptyList<ProgressPull.Conflict>(), a.conflicts + b.conflicts)
    }

    @Test
    fun `two devices that both moved since a shared sync are told once, naming both`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        val b = SyncDevice("device-b")
        a.read(book, page = 30, at = moment(1))
        a.sync(place, moment(2))
        b.sync(place, moment(3))
        a.read(book, page = 40, at = moment(4))
        b.read(book, page = 50, at = moment(5))

        a.sync(place, moment(6))
        b.sync(place, moment(7))
        a.sync(place, moment(8))
        b.sync(place, moment(9))

        val notices = a.conflicts + b.conflicts
        assertEquals(1, notices.size)
        assertEquals(ReadingPosition.Page(50, 100), notices.single().resolved.position)
        assertEquals(ReadingPosition.Page(40, 100), notices.single().discarded)
        assertEquals(ReadingPosition.Page(50, 100), a.position(book)?.position)
    }

    @Test
    fun `a publication finished on one device stays finished on both`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        val b = SyncDevice("device-b")
        a.read(book, page = 30, at = moment(1))
        a.library = a.library.copy(progress = a.library.progress.map { it.finished(true, moment(2)) })
        b.read(book, page = 45, at = moment(3))

        a.sync(place, moment(4))
        b.sync(place, moment(5))
        a.sync(place, moment(6))

        assertTrue(a.position(book)!!.isFinished)
        assertTrue(b.position(book)!!.isFinished)
        assertTrue(place.document().library.progress.single().isFinished)
    }
}
