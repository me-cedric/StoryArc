package app.storyarc.feature.library

import android.content.Context
import android.net.ConnectivityManager
import android.os.Looper.getMainLooper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * A held queue has to start again by itself, without the reader going back to the screen.
 *
 * `offline-downloads` promises that a download paused for Wi-Fi "resumes automatically when
 * [Wi-Fi] returns". [DownloadQueue.reconsider] was written for that promise and had no caller
 * on either platform, so the promise was kept only by accident: a reader who queued a
 * download on mobile data, then walked into Wi-Fi range, found a queue that stayed stopped
 * until something else happened to pump it.
 *
 * Four claims:
 *
 * - **The network changed.** The queue is told, and it starts its pending transfer with
 *   nothing else called.
 * - **The same notice, several times.** `registerDefaultNetworkCallback` reports an interface
 *   coming up more than once, and starting one transfer twice would be worse than the defect
 *   being fixed.
 * - **Room was freed.** Removing a finished download drops `bytesOnDisk` below the reader's
 *   limit, and the queue held by that limit starts.
 * - **The queue ended.** The callback is unregistered, so it does not outlive the page.
 *
 * The connection is injected. `onWifi` is a flow, and every test but the last hands the queue
 * one it drives itself, so no test depends on the machine's real connection. The last test
 * takes the real one, because what it asserts is the registration.
 *
 * Nothing here waits on a transfer, which goes to an address that resolves to nothing. The
 * record reaches `Running` in `pump`, before the transfer coroutine reaches its first
 * suspension. iOS asserts the same four things in `DownloadQueueWakingTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueWakingTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(vararg downloads: Download): DownloadStore =
        DownloadStore.open(context).apply { save(DownloadLibrary(downloads.toList())) }

    private fun queued(id: String) = Download(
        id = id,
        title = "Harbour Lights 04",
        remote = "https://example.invalid/hl04.epub",
        mediaType = "application/epub+zip",
        state = Download.State.Queued,
        expectedBytes = 8_400_000,
    )

    private fun finished(id: String, bytes: Long) = Download(
        id = id,
        title = "Harbour Lights 01",
        remote = "https://example.invalid/hl01.epub",
        mediaType = "application/epub+zip",
        state = Download.State.Finished,
        expectedBytes = bytes,
        downloadedBytes = bytes,
    )

    /**
     * **The network changed.** Wi-Fi-only is on and the device is on mobile data, so the queue
     * holds. The only call after that is the report of the new connection.
     */
    @Test
    fun `a queue waiting for wifi starts its transfer when wifi returns`() {
        val id = "wifi-returns"
        val wifi = MutableStateFlow(false)
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store(queued(id)),
            settings = { AppSettings(downloadOverWifiOnly = true) },
            onWifi = wifi,
        )
        shadowOf(getMainLooper()).idle()

        assertEquals(DownloadQueue.Held.WaitingForWifi, queue.held())
        assertEquals(Download.State.Queued, queue.library.value[id]?.state)

        wifi.value = true

        assertNull(queue.held())
        assertEquals(Download.State.Running, queue.library.value[id]?.state)
    }

    /**
     * **The same notice, several times.** `pump` is what makes a storm safe: it marks the
     * record running before it returns, so the next pump no longer sees it queued.
     *
     * The credential is asked for once per started transfer, on the way into the fetch and
     * before the coroutine suspends, so counting those calls counts the starts.
     */
    @Test
    fun `repeated network notices do not start the same download twice`() {
        val id = "no-double-start"
        var starts = 0
        val wifi = MutableSharedFlow<Boolean>(extraBufferCapacity = 8)
        DownloadQueue(
            context,
            CertificatePins(),
            store(queued(id)),
            credential = {
                starts += 1
                null
            },
            settings = { AppSettings(downloadOverWifiOnly = true) },
            onWifi = wifi,
        )
        shadowOf(getMainLooper()).idle()

        repeat(5) { wifi.tryEmit(true) }

        assertEquals("Five notices, one transfer.", 1, starts)
    }

    /**
     * **Room was freed.** The reader's own limit is reached, so the queue is held. Deleting a
     * finished publication is the one remedy the requirement names, and it has to be enough
     * on its own.
     */
    @Test
    fun `a queue held by the storage limit starts when room is freed`() {
        val kept = "kept"
        val wanted = "wanted"
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store(finished(kept, 2_000_000_000), queued(wanted)),
            settings = { AppSettings(maximumDownloadBytes = 1_000_000_000) },
            onWifi = MutableStateFlow(true),
        )
        shadowOf(getMainLooper()).idle()

        assertEquals(DownloadQueue.Held.StorageFull, queue.held())
        assertEquals(Download.State.Queued, queue.library.value[wanted]?.state)

        queue.remove(kept)

        assertNull(queue.held())
        assertEquals(Download.State.Running, queue.library.value[wanted]?.state)
    }

    /**
     * **The queue ended.** A `ConnectivityManager.NetworkCallback` outlives the object that
     * registered it until somebody unregisters it, and this queue is built again for every
     * catalogue page a reader opens.
     *
     * The queue is a `RememberObserver`, so Compose forgets it with the page that remembered
     * it. This test is that call, made by hand.
     */
    @Test
    fun `forgetting the queue unregisters its network callback`() {
        val manager = context.getSystemService(ConnectivityManager::class.java)!!
        val before = shadowOf(manager).networkCallbacks.size

        val queue = DownloadQueue(context, CertificatePins(), store())
        shadowOf(getMainLooper()).idle()
        assertEquals(before + 1, shadowOf(manager).networkCallbacks.size)

        queue.onForgotten()
        shadowOf(getMainLooper()).idle()

        assertEquals(before, shadowOf(manager).networkCallbacks.size)
    }
}
