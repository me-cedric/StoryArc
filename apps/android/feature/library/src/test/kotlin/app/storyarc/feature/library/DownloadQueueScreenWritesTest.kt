package app.storyarc.feature.library

import android.content.Context
import android.os.Looper.getMainLooper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.DownloadStore
import java.util.Date
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * One app-level download queue is the only writer of the download store.
 *
 * dl-core 1.1: a queue keyed per catalogue held its own in-memory copy of the download store's
 * records. Two of them open over the same store, or one of them beside a screen with no queue
 * of its own writing [DownloadStore] directly, each saved over whatever the other had just
 * written -- a Kavita keep or a source removal undone by the next catalogue's queue pumping.
 * [AppDependencies] now hands out one instance for however many catalogues are open; what this
 * suite proves is that the writes a screen with no transfer to run makes --
 * [DownloadQueue.reorder], [DownloadQueue.record], [DownloadQueue.removeAfterFinishing],
 * [DownloadQueue.restore] and [DownloadQueue.removingAll] -- go through that one instance's own
 * cache rather than a fresh [DownloadStore] read, so a later save of the same cache does not
 * undo them. iOS's `DownloadQueueSharedTests` makes the same four claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueScreenWritesTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(): DownloadStore = DownloadStore.open(context).apply { reset() }

    private fun queue(store: DownloadStore) = DownloadQueue(
        context,
        CertificatePins(),
        store,
        settings = { AppSettings() },
        onWifi = MutableStateFlow(true),
    )

    private fun acquisition(name: String) = OpdsAcquisition(
        href = "https://example.invalid/$name.epub",
        mediaType = "application/epub+zip",
        kind = OpdsAcquisition.Kind.OPEN,
    )

    @Test
    fun `a download enqueued from one page's call is visible to another page's own call`() {
        val store = store()
        val sourceA = UUID.randomUUID()
        val sourceB = UUID.randomUUID()

        // The one app-level queue, asked for twice -- once as each of two catalogue pages
        // would ask `AppDependencies.queue` for it -- and each enqueuing an entry the *other*
        // page's catalogue happens to number the same way.
        val page1 = queue(store)
        page1.enqueue(
            OpdsEntry(id = "entry-1", title = "From A"),
            acquisition("a"),
            sourceId = sourceA,
        )
        val page2 = page1
        page2.enqueue(
            OpdsEntry(id = "entry-1", title = "From B"),
            acquisition("b"),
            sourceId = sourceB,
        )

        // Both records exist, distinctly, because they are the same queue -- and neither
        // page's enqueue overwrote the other's the way two separate in-memory copies would.
        assertEquals("From A", page1.library.value[page1.downloadId("entry-1", sourceA)]?.title)
        assertEquals("From B", page1.library.value[page1.downloadId("entry-1", sourceB)]?.title)
        assertEquals(2, page1.library.value.downloads.size)
    }

    @Test
    fun `a record written through the queue survives an unrelated enqueue afterwards`() {
        val store = store()
        val queue = queue(store)

        // A Kavita keep, or a local import -- a completed download `record` files without
        // this queue's own transfer having run it.
        val kept = Download(
            id = "kavita:server-1:9",
            sourceId = UUID.randomUUID(),
            title = "Kept chapter",
            remote = "https://kavita.invalid/chapter/9",
            mediaType = "application/vnd.comicbook+zip",
            state = Download.State.Finished,
            expectedBytes = 4_000,
            downloadedBytes = 4_000,
            completedAt = Date(),
        )
        queue.record(kept)

        // The write this queue would make for something unrelated -- an ordinary enqueue,
        // which saves the queue's own cached library to the store. Before this queue was the
        // only writer, a second in-memory copy making this same save would have written the
        // kept chapter straight back out of existence.
        queue.enqueue(OpdsEntry(id = "entry-2", title = "Something else"), acquisition("c"))

        assertNotNull(
            "The queue's own later save overwrote the kept chapter.",
            queue.library.value[kept.id],
        )
        assertNotNull(
            "The kept chapter did not survive on disk either.",
            store.library()[kept.id],
        )
    }

    @Test
    fun `removing a source's downloads through the queue leaves the other source's alone`() {
        val store = store()
        val queue = queue(store)
        val gone = UUID.randomUUID()
        val kept = UUID.randomUUID()

        queue.enqueue(OpdsEntry(id = "entry-1", title = "Goes"), acquisition("a"), sourceId = gone)
        queue.enqueue(OpdsEntry(id = "entry-1", title = "Stays"), acquisition("b"), sourceId = kept)

        val removed = queue.removingAll(gone)

        assertEquals(1, removed.size)
        assertNull(queue.library.value[queue.downloadId("entry-1", gone)])
        assertEquals("Stays", queue.library.value[queue.downloadId("entry-1", kept)]?.title)
        // The removal is the queue's own save, not a separate write a later pump could undo.
        assertEquals(1, store.library().downloads.size)
    }

    @Test
    fun `a removal made through the queue can be undone through the same queue`() = runTest {
        val store = store()
        val queue = queue(store)
        val finished = Download(
            id = "finished-1",
            title = "Harbour Lights 02",
            remote = "https://example.invalid/hl02.epub",
            mediaType = "application/epub+zip",
            state = Download.State.Finished,
            expectedBytes = 500,
            downloadedBytes = 500,
            completedAt = Date(),
        )
        queue.record(finished)
        val file = store.location(finished)
        file.parentFile?.mkdirs()
        file.writeText("bytes")

        val removed = queue.removeAfterFinishing(finished.id)
        assertNotNull("Nothing to undo -- the finished file was not found.", removed)
        assertNull(queue.library.value[finished.id])

        queue.restore(removed!!)

        assertNotNull(
            "Restoring through the queue did not put the record back in its own cache.",
            queue.library.value[finished.id],
        )
        assertTrue(file.exists())
    }

    @Test
    fun `clearing through the queue is not undone by the queue's next save`() {
        val store = store()
        val queue = queue(store)
        queue.enqueue(OpdsEntry(id = "entry-1", title = "Cleared"), acquisition("a"))
        queue.enqueue(OpdsEntry(id = "entry-2", title = "Cleared too"), acquisition("b"))

        queue.clearing()
        // The next write the queue makes for something unrelated. A clear written to the store
        // behind the queue came back here, with every record the queue still held.
        queue.enqueue(OpdsEntry(id = "entry-3", title = "After"), acquisition("c"))

        assertEquals(listOf("entry-3"), store.library().downloads.map { it.id })
        assertEquals(listOf("entry-3"), queue.library.value.downloads.map { it.id })
    }

    @Test
    fun `the size a confirmation states is found under the page's own source`() {
        val queue = queue(store())
        val source = UUID.randomUUID()
        val entry = OpdsEntry(id = "entry-1", title = "Sized")
        queue.record(
            Download(
                id = queue.downloadId(entry.id, source),
                sourceId = source,
                title = entry.title,
                remote = "https://example.invalid/entry-1.epub",
                mediaType = "application/epub+zip",
                expectedBytes = 4_000,
            ),
        )

        assertEquals(4_000L, queue.statedBytes(entry, source))
    }

    @Test
    fun `a download that steps down from its source's https is refused`() {
        val source = UUID.randomUUID()
        // The app-level queue has no origin of its own; the record's source supplies it.
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store(),
            sourceOrigin = { id -> OpdsOrigin.of("https://library.invalid").takeIf { id == source } },
            settings = { AppSettings() },
            onWifi = MutableStateFlow(true),
        )
        val entry = OpdsEntry(id = "entry-1", title = "Cleartext")
        val cleartext = OpdsAcquisition(
            href = "http://library.invalid/entry-1.epub",
            mediaType = "application/epub+zip",
            kind = OpdsAcquisition.Kind.OPEN,
        )

        queue.enqueue(entry, cleartext, sourceId = source)
        shadowOf(getMainLooper()).idle()

        val state = queue.library.value[queue.downloadId(entry.id, source)]?.state
        assertEquals(
            "The queue fetched a book over cleartext from an https catalogue.",
            CatalogueMessages.describe(context, OpdsError.RefusedAddress),
            (state as? Download.State.Failed)?.reason,
        )
    }
}
