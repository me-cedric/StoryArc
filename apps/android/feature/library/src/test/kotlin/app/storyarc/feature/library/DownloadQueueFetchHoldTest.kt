package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A reader who presses *Read* on a download that is failed or paused has to get a transfer,
 * not a [kotlinx.coroutines.CompletableDeferred] nothing is ever going to complete.
 *
 * `fetch` enqueues before it waits, and [DownloadLibrary.queueing] is a no-op once a
 * publication's id is already known -- right for a fresh tap on something already queued or
 * running, wrong here: a failed download has no attempts left and a reader-paused one stays
 * paused until asked, so neither state resolves itself and neither is what `pump` starts.
 * Before the fix, `fetch` on either left the record exactly as it was and waited for ever.
 *
 * Launched with [Dispatchers.Unconfined] rather than joined: everything `fetch` does before
 * `waiter.await()` -- the requeue, `promote`, `pump` -- is ordinary (non-suspending) code, so
 * an unconfined launch runs all of it inline and only then suspends, with no looper to idle.
 * Nothing here waits for `fetch` to return, which -- under the bug -- would hang the test
 * along with it. iOS asserts the first two cases in `DownloadQueueFetchHoldTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueFetchHoldTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(id: String): DownloadStore = DownloadStore.open(context).apply {
        save(
            DownloadLibrary(
                listOf(
                    Download(
                        id = id,
                        title = "Harbour Lights 03",
                        remote = "https://example.invalid/hl03.epub",
                        mediaType = "application/epub+zip",
                        state = Download.State.Queued,
                        expectedBytes = 8_400_000,
                        downloadedBytes = 190_000,
                    ),
                ),
            ),
        )
    }

    private fun queue(store: DownloadStore, onWifi: Boolean = true) = DownloadQueue(
        context,
        CertificatePins(),
        store,
        settings = { AppSettings(downloadOverWifiOnly = false) },
        onWifi = MutableStateFlow(onWifi),
    )

    private fun entryAndAcquisition(id: String) = OpdsEntry(id = id, title = "Harbour Lights 03") to
        OpdsAcquisition(
            href = "https://example.invalid/hl03.epub",
            mediaType = "application/epub+zip",
            kind = OpdsAcquisition.Kind.OPEN,
        )

    @Test
    fun `a failed download is put back in the queue rather than waited on forever`() {
        val id = "fetch-failed-${UUID.randomUUID()}"
        val store = store(id)
        store.save(store.library().marking(id, Download.State.Failed("The server did not answer in time.", 3)))
        val queue = queue(store)
        val (entry, acquisition) = entryAndAcquisition(id)

        CoroutineScope(Dispatchers.Unconfined).launch { queue.fetch(entry, acquisition) }

        assertEquals(Download.State.Running, queue.library.value[id]?.state)
    }

    @Test
    fun `a download the reader paused is put back in the queue rather than waited on forever`() {
        val id = "fetch-paused-${UUID.randomUUID()}"
        val queue = queue(store(id))
        // The reader's own pause, through the queue's own action -- the same one the
        // Downloads screen's Stop control reaches.
        queue.pause(id)
        val (entry, acquisition) = entryAndAcquisition(id)

        CoroutineScope(Dispatchers.Unconfined).launch { queue.fetch(entry, acquisition) }

        assertEquals(Download.State.Running, queue.library.value[id]?.state)
    }

    @Test
    fun `a download paused for Wi-Fi is left for the connection to resolve, not forced`() {
        val id = "fetch-wifi-${UUID.randomUUID()}"
        val store = DownloadStore.open(context).apply {
            save(
                DownloadLibrary(
                    listOf(
                        Download(
                            id = id,
                            title = "Harbour Lights 03",
                            remote = "https://example.invalid/hl03.epub",
                            mediaType = "application/epub+zip",
                            state = Download.State.Queued,
                        ),
                    ),
                ),
            )
        }
        // Wi-Fi-only on and no Wi-Fi at construction, so the queue's own `init` holds it --
        // the same hold `DownloadQueueConnectionTest` drives.
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store,
            settings = { AppSettings(downloadOverWifiOnly = true) },
            onWifi = MutableStateFlow(false),
        )
        val (entry, acquisition) = entryAndAcquisition(id)

        CoroutineScope(Dispatchers.Unconfined).launch { queue.fetch(entry, acquisition) }

        assertEquals(
            Download.State.Paused(Download.Pause.WAITING_FOR_WIFI),
            queue.library.value[id]?.state,
        )
    }
}
