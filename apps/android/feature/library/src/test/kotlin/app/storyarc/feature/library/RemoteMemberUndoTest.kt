package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The undo of a group download, for a member it queued from its catalogue.
 *
 * The row is `srv:<source>:opds:<entry>` and the queue keys the download
 * `opds:<source>:<entry>`. An undo by the row's id took nothing back, and the member went on
 * downloading under a snackbar that said it had been undone. iOS asserts the same in
 * `RemoteMemberUndoTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RemoteMemberUndoTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val entry = OpdsEntry(id = "hl09", title = "Harbour Lights 09")

    private val acquisition = OpdsAcquisition(
        href = "https://example.invalid/hl09.epub",
        mediaType = "application/epub+zip",
        kind = OpdsAcquisition.Kind.OPEN,
    )

    private val store: DownloadStore by lazy {
        DownloadStore.open(context).apply { save(DownloadLibrary()) }
    }

    // Wi-Fi-only on and no Wi-Fi, so nothing starts and the record is all this measures.
    private val queue: DownloadQueue by lazy {
        DownloadQueue(
            context,
            CertificatePins(),
            store,
            settings = { AppSettings(downloadOverWifiOnly = true) },
            onWifi = MutableStateFlow(false),
        )
    }

    @Test
    fun `undoing a group download takes back a member it queued from its catalogue`() {
        val source = UUID.randomUUID()

        val queued = RemoteMemberResolution.enqueue(entry, acquisition, source, queue)
        KeepOffline.forget(store, setOfNotNull(queued), queue)

        assertNull(
            "The member is still queued after its undo.",
            queue.library.value[queue.downloadId(entry.id, source)],
        )
    }

    @Test
    fun `a member the reader had already queued is not the group's to take back`() {
        val source = UUID.randomUUID()
        queue.enqueue(entry, acquisition, sourceId = source)

        assertNull(RemoteMemberResolution.enqueue(entry, acquisition, source, queue))
        assertNotNull(queue.library.value[queue.downloadId(entry.id, source)])
    }
}
