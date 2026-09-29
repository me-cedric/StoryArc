package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * An OPDS download is keyed by its source as well as its raw entry id.
 *
 * dl-core 1.2: two catalogues that number their entries the same way -- `entry-1`, `entry-2`
 * -- shared one record and one file, because the queue kept a download only under its entry
 * id. A source removal ([DownloadLibrary.removingAll]) found nothing to remove either, for
 * the same reason: the record carried no source at all.
 *
 * iOS asserts the same claims in `DownloadQueueSourceKeyingTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueSourceKeyingTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(): DownloadStore = DownloadStore.open(context).apply { reset() }

    private fun queue(
        store: DownloadStore,
        sourceId: UUID? = null,
        origin: OpdsOrigin? = null,
    ) = DownloadQueue(
        context,
        CertificatePins(),
        store,
        origin = origin,
        sourceId = sourceId,
        settings = { AppSettings() },
        onWifi = MutableStateFlow(true),
    )

    private val acquisition = OpdsAcquisition(
        href = "https://example.invalid/entry-1.epub",
        mediaType = "application/epub+zip",
        kind = OpdsAcquisition.Kind.OPEN,
    )
    private val entry = OpdsEntry(id = "entry-1", title = "Harbour Lights 01")

    @Test
    fun `two sources that number their entries the same way are not the same record`() {
        val first = UUID.randomUUID()
        val second = UUID.randomUUID()
        val store = store()

        val queueA = queue(store, sourceId = first)
        queueA.enqueue(entry, acquisition)

        // Built after A's write lands, so it starts from A's record rather than racing it --
        // two live queues over one store fighting each other is dl-core 1.1, not this test.
        val queueB = queue(store, sourceId = second)
        queueB.enqueue(entry, acquisition)

        assertNotEquals(queueA.downloadId("entry-1"), queueB.downloadId("entry-1"))
        val saved = store.library()
        assertEquals(2, saved.downloads.size)
        assertEquals(first, saved[queueA.downloadId("entry-1")]?.sourceId)
        assertEquals(second, saved[queueB.downloadId("entry-1")]?.sourceId)
    }

    @Test
    fun `a queued download carries its source id, so a source removal finds it`() {
        val source = UUID.randomUUID()
        val queue = queue(store(), sourceId = source)

        queue.enqueue(entry, acquisition)

        val (kept, removed) = queue.library.value.removingAll(source)
        assertEquals(1, removed.size)
        assertTrue(kept.downloads.isEmpty())
    }

    @Test
    fun `the download id is namespaced by source, the way a Kavita chapter already is`() {
        val source = UUID.randomUUID()
        val queue = queue(store(), sourceId = source)
        assertEquals("opds:$source:entry-3", queue.downloadId("entry-3"))
    }

    @Test
    fun `a stray record this catalogue's origin owns is re-keyed when the queue opens`() {
        val origin = requireNotNull(OpdsOrigin.of("https://library.example"))
        val remote = "https://library.example/download/entry-7.epub"
        val store = store()
        // What a pre-1.2 build wrote: no source, the bare entry id.
        store.save(
            DownloadLibrary(
                listOf(
                    Download(
                        id = "entry-7",
                        title = "Harbour Lights 07",
                        remote = remote,
                        mediaType = "application/epub+zip",
                        state = Download.State.Finished,
                        downloadedBytes = 1_000,
                    ),
                ),
            ),
        )

        val source = UUID.randomUUID()
        val migrated = queue(store, sourceId = source, origin = origin)

        val record = migrated.library.value["opds:$source:entry-7"]
        assertEquals(source, record?.sourceId)
        assertNull(
            "The old key is still readable, so a second source could still collide with it.",
            migrated.library.value["entry-7"],
        )
        // Written back, so a queue built again from the same store sees the fixed record
        // rather than migrating it a second time.
        assertNull(store.library()["entry-7"])
    }

    @Test
    fun `a record from a different origin is left alone`() {
        val origin = requireNotNull(OpdsOrigin.of("https://library.example"))
        val store = store()
        store.save(
            DownloadLibrary(
                listOf(
                    Download(
                        id = "entry-7",
                        title = "Harbour Lights 07",
                        remote = "https://elsewhere.invalid/entry-7.epub",
                        mediaType = "application/epub+zip",
                        state = Download.State.Finished,
                        downloadedBytes = 1_000,
                    ),
                ),
            ),
        )

        val untouched = queue(store, sourceId = UUID.randomUUID(), origin = origin)

        assertTrue(
            "A record this origin does not own was migrated anyway.",
            untouched.library.value["entry-7"] != null,
        )
    }
}
