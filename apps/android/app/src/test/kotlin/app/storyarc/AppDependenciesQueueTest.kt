package app.storyarc

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.SourceStore
import app.storyarc.feature.library.DownloadService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The one app-level download queue is built when the app opens, not when a reader first
 * happens to open a catalogue.
 *
 * dl-core 1.3: the queue used to come to life only from `AppScreens.kt`'s
 * `dependencies.queue`, so a download left queued or held when the process died stayed that
 * way -- nothing restarted it -- until some catalogue page was opened. iOS asserts the same
 * claim in `StoryArcApp.init` by building `DownloadQueue.shared()` there; Android's queue is
 * `AppDependencies.queue`, and this is the same claim for it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppDependenciesQueueTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `AppDependencies open builds the queue itself, before any screen asks for it`() {
        val dependencies = AppDependencies.open(context)

        assertTrue(
            "The queue is still unbuilt after open() returned, so nothing restarts a held " +
                "or queued download until a catalogue page happens to be opened.",
            dependencies.queueIsBuilt,
        )
    }

    @Test
    fun `A download left running when the process died is picked up again once the app opens`() {
        // What a process death leaves behind: nothing outside this process was actually
        // carrying it, so a record still marked `Running` is one the queue's own `init` has
        // to notice and restart -- `DownloadLibrary.reclaiming` -- rather than one left to
        // wait for ever on a transfer that no longer exists.
        shadowOf(application).clearStartedServices()
        val leftRunning = Download(
            id = "left-running",
            title = "Harbour Lights 05",
            remote = "https://example.invalid/hl05.epub",
            mediaType = "application/epub+zip",
            state = Download.State.Running,
            expectedBytes = 1_000,
        )
        app.storyarc.core.persistence.DownloadStore.open(context).save(
            DownloadLibrary(downloads = listOf(leftRunning)),
        )

        AppDependencies.open(context)

        // The foreground service is asked to follow a transfer only when the queue actually
        // starts one -- `DownloadQueueEnqueueTest` proves the same signal for an ordinary
        // enqueue. Seeing it here, with no screen having asked for the queue at all, is what
        // "at app start" means: nothing but `open()` could have started this.
        val followed = shadowOf(application).allStartedServices.mapNotNull { it.component?.className }
        assertTrue(
            "Nothing restarted the download left running when the process died: $followed",
            DownloadService::class.java.name in followed,
        )
    }

    @Test
    fun `A download recorded before source-keyed ids is re-keyed when the app queue is built`() {
        // dl-core 1.2's migration, reached the way the app reaches it: the one queue is the
        // only one built, and it has no catalogue origin of its own to match a stray against.
        val source = Source(
            displayName = "Library",
            kind = SourceKind.OPDS_CATALOG,
            locator = "https://library.example",
        )
        SourceStore.open(context).save(SourceRegistry(sources = listOf(source)))
        app.storyarc.core.persistence.DownloadStore.open(context).save(
            DownloadLibrary(
                downloads = listOf(
                    Download(
                        id = "entry-7",
                        title = "Harbour Lights 07",
                        remote = "https://library.example/download/entry-7.epub",
                        mediaType = "application/epub+zip",
                        state = Download.State.Finished,
                        downloadedBytes = 1_000,
                    ),
                ),
            ),
        )

        val queue = AppDependencies.open(context).queue

        assertEquals(source.id, queue.library.value["opds:${source.id}:entry-7"]?.sourceId)
        assertNull(
            "The stray kept its bare entry id, so another catalogue can still collide with it.",
            queue.library.value["entry-7"],
        )
    }
}
