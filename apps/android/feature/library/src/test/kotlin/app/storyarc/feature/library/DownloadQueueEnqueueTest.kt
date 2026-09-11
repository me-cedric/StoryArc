package app.storyarc.feature.library

import android.app.Application
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
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * What one call to [DownloadQueue.enqueue] leaves behind: a record that names its source, and a
 * platform that has been told there is work to do.
 *
 * Both are what a download started from a publication page needs and a download started from the
 * catalogue page already had. The record's source is how the finished copy folds onto the library
 * row it came from -- [LibraryViewModel.adoptDownloads] reads it -- and the service is how the
 * transfer outlives the page, which `offline-downloads` asks for.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueEnqueueTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val entry = OpdsEntry(id = "hl09", title = "Harbour Lights 09")

    private val acquisition = OpdsAcquisition(
        href = "https://example.invalid/hl09.epub",
        mediaType = "application/epub+zip",
        kind = OpdsAcquisition.Kind.OPEN,
    )

    private fun store(): DownloadStore =
        DownloadStore.open(context).apply { save(DownloadLibrary()) }

    @Test
    fun `a download enqueued for a source records that source`() {
        val source = UUID.randomUUID()
        // Wi-Fi-only on and no Wi-Fi, so nothing starts and the record is the only thing
        // this measures. The same injected connection `DownloadQueueConnectionTest` uses.
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store(),
            settings = { AppSettings(downloadOverWifiOnly = true) },
            onWifi = MutableStateFlow(false),
        )

        queue.enqueue(entry, acquisition, sourceId = source)

        assertEquals(
            "The finished copy has no source to fold onto the library row it came from.",
            source,
            queue.library.value[entry.id]?.sourceId,
        )
    }

    @Test
    fun `a running transfer asks the foreground service to follow it`() {
        // Cleared first, so a service started while the queue was built cannot answer for the
        // transfer. A queue with nothing to do stops the service rather than starting it, so
        // every intent left here was asked for by the download below.
        shadowOf(application).clearStartedServices()
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store(),
            settings = { AppSettings() },
            onWifi = MutableStateFlow(true),
        )

        queue.enqueue(entry, acquisition, sourceId = UUID.randomUUID())

        // Asserted without idling the looper: the pump marks the record running and asks the
        // platform to follow it before it returns, and a transfer that has already reached the
        // network could have finished or failed by the time an idled looper hands back control.
        assertEquals(Download.State.Running, queue.library.value[entry.id]?.state)
        val followed = shadowOf(application).allStartedServices.mapNotNull { it.component?.className }
        assertTrue(
            "Nothing asked the platform to keep the process alive, so the transfer ends with " +
                "the page the reader started it from: $followed",
            DownloadService::class.java.name in followed,
        )
    }

    @Test
    fun `a record the store already holds is not queued again by enqueue alone`() {
        // The reason `PublicationCopy.begin` follows `enqueue` with `resume`. A publication
        // tried once and left failed -- or one whose source was removed and added again --
        // keeps its record, and `DownloadLibrary.queueing` keeps the record it has rather than
        // the one it is given. Photographed on a phone: the page drew *Download it*, the tap
        // queued nothing, and no transfer began.
        val store = store()
        store.save(
            DownloadLibrary(
                downloads = listOf(
                    Download(
                        id = entry.id,
                        title = entry.title,
                        remote = acquisition.href,
                        mediaType = acquisition.mediaType,
                        state = Download.State.Failed(reason = "it stopped", attempts = 3),
                    ),
                ),
            ),
        )
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store,
            settings = { AppSettings(downloadOverWifiOnly = true) },
            onWifi = MutableStateFlow(false),
        )

        queue.enqueue(entry, acquisition, sourceId = UUID.randomUUID())

        assertTrue(
            "enqueue restarted a failed record on its own, so the resume beside it is dead " +
                "code and this test is the wrong shape.",
            queue.library.value[entry.id]?.state is Download.State.Failed,
        )

        queue.resume(entry.id)

        // Queued and then held in the same call: `resume` pumps, and the pump applies the
        // Wi-Fi rule this queue was built with. The hold is the proof the queue took the row --
        // a record still `Failed` is a record nothing picked up.
        assertEquals(
            "resume is what moves a record the store already held back into the queue.",
            Download.State.Paused(Download.Pause.WAITING_FOR_WIFI),
            queue.library.value[entry.id]?.state,
        )
    }
}
