package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.DownloadStore
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Global pause, resume and cancel, sent to the one app-level queue.
 *
 * `offline-downloads`' second requirement asks for "per-item and global pause, resume,
 * cancel" together. [DownloadQueue.pause] and [DownloadQueue.resume] already existed with no
 * caller from the Downloads destination, and nothing offered the global three at all --
 * `DownloadsParts.kt` drew reorder and Stop only. iOS asserts the same three claims in
 * `DownloadQueueGlobalControlsTests`.
 *
 * `record` rather than `enqueue`: it writes a state straight into the cache with no `pump()`
 * behind it, so a seeded row stays exactly where this suite puts it until the method under
 * test touches it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueGlobalControlsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(): DownloadStore = DownloadStore.open(context).apply { reset() }

    private fun queue(store: DownloadStore) = DownloadQueue(
        context,
        CertificatePins(),
        store,
        settings = { AppSettings() },
        onWifi = MutableStateFlow(true),
    )

    private fun download(id: String, state: Download.State) = Download(
        id = id,
        title = "Harbour Lights $id",
        remote = "https://example.invalid/$id.epub",
        mediaType = "application/epub+zip",
        state = state,
    )

    @Test
    fun `pausing every download pauses only what was queued or running`() {
        val queue = queue(store())
        queue.record(download("running", Download.State.Running))
        queue.record(download("paused", Download.State.Paused(Download.Pause.BY_READER)))
        queue.record(download("finished", Download.State.Finished))

        queue.pauseAll()

        assertEquals(Download.State.Paused(Download.Pause.BY_READER), queue.library.value["running"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.BY_READER), queue.library.value["paused"]?.state)
        assertEquals(
            "A finished download was touched.",
            Download.State.Finished,
            queue.library.value["finished"]?.state,
        )
    }

    @Test
    fun `resuming every download puts what was paused or failed back in the queue, and nothing else`() {
        val queue = queue(store())
        queue.record(download("paused", Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)))
        queue.record(download("failed", Download.State.Failed("it stopped", 3)))
        queue.record(download("finished", Download.State.Finished))

        queue.resumeAll()

        // Neither is left where it was: `pump()` takes the connection this suite built the
        // queue on and starts the first it finds room for, which is why this does not pin
        // `Queued` specifically.
        assertTrue(
            queue.library.value["paused"]?.state == Download.State.Queued ||
                queue.library.value["paused"]?.state == Download.State.Running,
        )
        assertTrue(
            queue.library.value["failed"]?.state == Download.State.Queued ||
                queue.library.value["failed"]?.state == Download.State.Running,
        )
        assertEquals(
            "A finished download was touched.",
            Download.State.Finished,
            queue.library.value["finished"]?.state,
        )
    }

    @Test
    fun `cancelling every download removes everything still pending, and keeps what finished`() {
        val queue = queue(store())
        queue.record(download("running", Download.State.Running))
        queue.record(download("paused", Download.State.Paused(Download.Pause.BY_READER)))
        queue.record(download("failed", Download.State.Failed("it stopped", 3)))
        queue.record(download("finished", Download.State.Finished))

        queue.cancelAll()

        assertNull(queue.library.value["running"])
        assertNull(queue.library.value["paused"])
        assertNull(queue.library.value["failed"])
        assertEquals(
            "A finished download was removed.",
            Download.State.Finished,
            queue.library.value["finished"]?.state,
        )
    }
}
