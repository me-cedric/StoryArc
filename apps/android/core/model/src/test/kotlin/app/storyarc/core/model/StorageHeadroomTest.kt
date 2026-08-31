package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `offline-downloads`' *Device storage is low*, asserted case for case. iOS's
 * `StorageHeadroomTests` asserts the same cases, which is how the two queues stay honest
 * about the one question that decides whether the app fills a reader's phone.
 */
class StorageHeadroomTest {
    private val reserve = StorageHeadroom.RESERVE_BYTES

    @Test
    fun `a volume with room to spare is not low`() {
        assertFalse(StorageHeadroom.isLow(reserve * 4))
        assertTrue(StorageHeadroom.hasRoom(reserve * 4))
    }

    @Test
    fun `a volume below the reserve is low even with nothing incoming`() {
        assertTrue(StorageHeadroom.isLow(reserve - 1))
        assertFalse(StorageHeadroom.hasRoom(reserve - 1))
    }

    @Test
    fun `exactly the reserve is room enough`() {
        assertFalse(StorageHeadroom.isLow(reserve))
    }

    @Test
    fun `an incoming file that would eat into the reserve is refused`() {
        // Twice the floor free, and a download that would leave one byte less than the
        // floor behind. The queue has to refuse it before it starts, not after.
        assertTrue(StorageHeadroom.isLow(reserve * 2, reserve + 1))
        assertFalse(StorageHeadroom.isLow(reserve * 2, reserve))
    }

    @Test
    fun `an unknown free space does not stop the queue`() {
        // AGENTS.md §2: offline is a normal state, not an error -- and a volume that
        // declines to report is not a full one. Refusing every download for want of a number
        // would be an invented failure the reader could never clear.
        assertFalse(StorageHeadroom.isLow(null))
        assertFalse(StorageHeadroom.isLow(null, reserve * 100))
        assertTrue(StorageHeadroom.hasRoom(null))
    }

    @Test
    fun `an unknown incoming size still has to clear the floor`() {
        // The usual case: an OPDS feed states no length, so the queue knows the volume and
        // not the file. The floor is the half of the rule it can still enforce.
        assertTrue(StorageHeadroom.isLow(reserve - 1, null))
        assertFalse(StorageHeadroom.isLow(reserve + 1, null))
    }

    @Test
    fun `nonsense numbers cannot make room appear`() {
        assertTrue(StorageHeadroom.isLow(-1))
        // A negative size would otherwise be subtracted as an addition.
        assertTrue(StorageHeadroom.isLow(reserve - 1, -reserve))
    }

    @Test
    fun `the reserve is the same number on both platforms`() {
        assertEquals(256L * 1024 * 1024, StorageHeadroom.RESERVE_BYTES)
    }
}

/**
 * The two library operations the shortage drives, which decide what a reader sees on every
 * row of the downloads screen. iOS's `DownloadSpaceHoldTests` asserts the same cases.
 */
class DownloadSpaceHoldTest {
    private fun download(id: String, state: Download.State) = Download(
        id = id,
        title = id,
        remote = "https://example.test/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
    )

    private val mixed = DownloadLibrary(
        listOf(
            download("queued", Download.State.Queued),
            download("running", Download.State.Running),
            download("reader", Download.State.Paused(Download.Pause.BY_READER)),
            download("failed", Download.State.Failed("the server refused", 2)),
            download("finished", Download.State.Finished),
        ),
    )

    @Test
    fun `queued and running are paused, and say why`() {
        val held = mixed.pausingForSpace()

        assertEquals(Download.State.Paused(Download.Pause.OUT_OF_SPACE), held["queued"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.OUT_OF_SPACE), held["running"]?.state)
    }

    @Test
    fun `a download the reader paused is not re-labelled`() {
        // The reason on the row is the reader's own, and overwriting it would resume their
        // download the moment space returned -- which is not what they asked for.
        assertEquals(
            Download.State.Paused(Download.Pause.BY_READER),
            mixed.pausingForSpace()["reader"]?.state,
        )
    }

    @Test
    fun `nothing is deleted, and a finished download keeps its state`() {
        val held = mixed.pausingForSpace()

        // `offline-downloads`: "never deletes a download without asking".
        assertEquals(mixed.downloads.size, held.downloads.size)
        assertEquals(Download.State.Finished, held["finished"]?.state)
        assertEquals(Download.State.Failed("the server refused", 2), held["failed"]?.state)
    }

    @Test
    fun `room returning puts back only what the shortage held`() {
        val released = mixed.pausingForSpace().resumingAfterSpace()

        assertEquals(Download.State.Queued, released["queued"]?.state)
        assertEquals(Download.State.Queued, released["running"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.BY_READER), released["reader"]?.state)
        assertEquals(Download.State.Failed("the server refused", 2), released["failed"]?.state)
        assertEquals(Download.State.Finished, released["finished"]?.state)
    }

    @Test
    fun `releasing a library that was never held changes nothing`() {
        assertEquals(mixed, mixed.resumingAfterSpace())
    }
}
