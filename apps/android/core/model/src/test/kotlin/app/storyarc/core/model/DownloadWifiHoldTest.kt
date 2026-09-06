package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The connection half of `offline-downloads`' *Wi-Fi only*, as a pure rule.
 *
 * "When the 'download over Wi-Fi only' setting is on and the device is on cellular, downloads
 * pause and state that they are waiting for Wi-Fi, and resume automatically when it returns."
 * The queue only started transfers, so a reader who began a download on Wi-Fi and walked out of
 * range kept downloading over mobile data: the setting protected the queue and not the transfer
 * already running.
 *
 * One pass answers both halves, so a connection that drops and returns cannot pause and resume
 * the same row twice in one call. iOS's `DownloadWifiHoldTests` asserts the same cases.
 */
class DownloadWifiHoldTest {

    private fun download(id: String, state: Download.State) = Download(
        id = id,
        title = id,
        remote = "file:///nowhere/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
    )

    private val mixed = DownloadLibrary(
        listOf(
            download("queued", Download.State.Queued),
            download("running", Download.State.Running),
            download("reader", Download.State.Paused(Download.Pause.BY_READER)),
            download("space", Download.State.Paused(Download.Pause.OUT_OF_SPACE)),
            download("failed", Download.State.Failed("the server refused", 2)),
            download("finished", Download.State.Finished),
        ),
    )

    @Test
    fun `a running transfer the connection forbids is paused and says why`() {
        val held = mixed.reconsideringWifi { false }

        val waiting = Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)
        assertEquals(waiting, held["running"]?.state)
        assertEquals(waiting, held["queued"]?.state)
    }

    @Test
    fun `a download the reader paused keeps their reason`() {
        val held = mixed.reconsideringWifi { false }

        assertEquals(Download.State.Paused(Download.Pause.BY_READER), held["reader"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.OUT_OF_SPACE), held["space"]?.state)
        assertEquals(Download.State.Failed("the server refused", 2), held["failed"]?.state)
        assertEquals(Download.State.Finished, held["finished"]?.state)
    }

    @Test
    fun `nothing is dropped and no fetched byte is forgotten`() {
        val partial = download("running", Download.State.Running)
            .copy(downloadedBytes = 4_000_000, expectedBytes = 8_400_000)
        val held = DownloadLibrary(listOf(partial)).reconsideringWifi { false }

        // Pausing is not cancelling: the record stays and the bytes counted against it stay
        // with it. `offline-downloads` resumes a held download rather than starting a new one.
        assertEquals(1, held.downloads.size)
        assertEquals(4_000_000L, held["running"]?.downloadedBytes)
        assertEquals(8_400_000L, held["running"]?.expectedBytes)
    }

    @Test
    fun `a download the connection permits is put back in the queue`() {
        val released = mixed.reconsideringWifi { false }.reconsideringWifi { true }

        assertEquals(Download.State.Queued, released["queued"]?.state)
        assertEquals(Download.State.Queued, released["running"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.BY_READER), released["reader"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.OUT_OF_SPACE), released["space"]?.state)
    }

    @Test
    fun `a permitted download is not paused while a forbidden one is`() {
        // `offline-downloads` grants the metered override "for that item only". The grant
        // decides one row and must not decide the row beside it.
        val held = mixed.reconsideringWifi { it.id == "running" }

        assertEquals(Download.State.Running, held["running"]?.state)
        assertEquals(
            Download.State.Paused(Download.Pause.WAITING_FOR_WIFI),
            held["queued"]?.state,
        )
    }

    @Test
    fun `a connection that changes nothing writes nothing`() {
        // The anti-thrash guarantee the queue depends on: a pass that alters no row returns
        // the same value, so the caller can compare and skip the write to the store.
        assertEquals(mixed, mixed.reconsideringWifi { true })
        val once = mixed.reconsideringWifi { false }
        assertEquals(once, once.reconsideringWifi { false })
    }
}

/**
 * What a screen with no queue is told the queue is waiting for.
 *
 * `offline-downloads` requires a held queue to say what it is waiting for, and the three
 * situations have three different remedies. The rule reads the records the queue wrote, which is
 * what lets a settings screen answer without holding a queue at all. iOS's `DownloadHoldTests`
 * asserts the same cases.
 */
class DownloadHoldTest {

    private fun download(id: String, state: Download.State, bytes: Long = 0) = Download(
        id = id,
        title = id,
        remote = "file:///nowhere/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
        downloadedBytes = bytes,
    )

    @Test
    fun `a queue with nothing waiting is not held`() {
        val library = DownloadLibrary(listOf(download("finished", Download.State.Finished, 9)))
        assertNull(library.hold(null))
        // The limit is reached and there is nothing to hold. A screen that announced a hold
        // here would be reporting a queue that is not waiting for anything.
        assertNull(library.hold(1))
    }

    @Test
    fun `a download waiting for wifi holds the queue`() {
        val library = DownloadLibrary(
            listOf(download("one", Download.State.Paused(Download.Pause.WAITING_FOR_WIFI))),
        )
        assertEquals(DownloadHold.WAITING_FOR_WIFI, library.hold(null))
    }

    @Test
    fun `the device's own shortage is named before anything the reader chose`() {
        val library = DownloadLibrary(
            listOf(
                download("one", Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)),
                download("two", Download.State.Paused(Download.Pause.OUT_OF_SPACE)),
            ),
        )
        assertEquals(DownloadHold.OUT_OF_SPACE, library.hold(null))
    }

    @Test
    fun `the reader's own maximum holds a queue that still has work`() {
        val library = DownloadLibrary(
            listOf(
                download("kept", Download.State.Finished, 2_000),
                download("wanted", Download.State.Queued),
            ),
        )
        assertEquals(DownloadHold.STORAGE_FULL, library.hold(1_000))
        assertTrue(library.isAtLimit(1_000))
        assertNull(library.hold(3_000))
        assertFalse(library.isAtLimit(3_000))
    }

    @Test
    fun `a download the reader paused is not a reason the queue is held`() {
        // The reader stopped it. A screen saying the queue is waiting for something would be
        // telling them to fix a condition they created and can undo on the row itself.
        val library = DownloadLibrary(
            listOf(download("one", Download.State.Paused(Download.Pause.BY_READER))),
        )
        assertNull(library.hold(null))
    }
}
