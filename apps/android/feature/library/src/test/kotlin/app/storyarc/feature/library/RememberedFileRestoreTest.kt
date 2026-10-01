package app.storyarc.feature.library

import android.app.Application
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.RememberedFiles
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * 10.10: a file another app handed over and the reader kept comes back on the shelf.
 *
 * Filed under [RememberedFiles.SOURCE_ID] rather than under no source at all, the way iOS
 * files one: `null` is the managed folder's own scope here
 * ([app.storyarc.feature.library.folderSourceOf]), walked on every scan, so a row filed
 * under it reads as unseen by that walk and is removed by it -- which a first version of
 * this fix did, the moment `restoreFolders` ran the managed-folder scan beside it.
 *
 * Real fixtures, copied out of the committed corpus like [ShelfLifecycleTest]'s: a row built
 * from bytes that are not really a comic proves nothing about the format sniff that is the
 * whole of what [RememberedFileRestore] asks of them.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RememberedFileRestoreTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
    private val corpus: File = File(
        requireNotNull(System.getProperty("storyarc.library.projectDir")) {
            "storyarc.library.projectDir is not set — see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    private fun library() = LibraryViewModel(application)

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        RememberedFiles.open(application).all().forEach { RememberedFiles.open(application).forget(it) }
    }

    @After
    fun tearDown() {
        RememberedFiles.open(application).all().forEach { RememberedFiles.open(application).forget(it) }
        Dispatchers.resetMain()
    }

    /** A real comic, copied out of the corpus so the format sniff that matters can run. */
    private fun comic(name: String = "single-page.cbz"): Uri {
        val directory = File(application.cacheDir, "remembered-restore-${name.hashCode()}")
        directory.mkdirs()
        val file = File(directory, name)
        corpus.resolve("comics/$name").copyTo(file, overwrite = true)
        return Uri.fromFile(file)
    }

    private fun missingFile(name: String): Uri = Uri.fromFile(File(application.cacheDir, "missing-$name"))

    /**
     * `restoreRememberedFiles` hops to the real `Dispatchers.IO` for the read, a genuine
     * background thread `UnconfinedTestDispatcher` does not touch -- so the test has to wait
     * for it rather than read the result the instant the call returns. Bounded, rather than a
     * bare `Thread.sleep`, so a regression that never completes fails in two seconds instead
     * of hanging the suite.
     */
    private fun awaitSettled(until: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 2_000
        while (!until() && System.currentTimeMillis() < deadline) Thread.sleep(10)
    }

    @Test
    fun `a remembered file is indexed and filed under its own source`() {
        val uri = comic()
        RememberedFiles.open(application).remember(uri)

        val library = library()
        library.restoreRememberedFiles()
        awaitSettled { library.publications.value.isNotEmpty() }

        val publication = library.publications.value.singleOrNull()
        assertEquals(RememberedFiles.SOURCE_ID, publication?.sourceId)
        assertEquals(uri.toString(), library.locations[publication?.id])
    }

    @Test
    fun `a remembered file that no longer resolves is forgotten, not reported`() {
        val uri = missingFile("Gone.cbz")
        val store = RememberedFiles.open(application)
        store.remember(uri)

        val library = library()
        library.restoreRememberedFiles()
        awaitSettled { store.all().none { it == uri } }

        assertTrue(library.publications.value.isEmpty())
        assertTrue(store.all().none { it == uri })
    }

    @Test
    fun `its own source is not the managed folder's scope, so a scan never removes it`() {
        // The regression itself: `FolderSource.folderSourceOf(null)` is the id every scan
        // walks on every pass. A remembered file filed under that id reads as a row that
        // id's walk did not see, and is reconciled away the moment any scan runs.
        val uri = comic()
        RememberedFiles.open(application).remember(uri)
        val library = library()
        library.restoreRememberedFiles()
        awaitSettled { library.publications.value.isNotEmpty() }
        val publicationId = library.publications.value.single().id

        library.rescan()
        awaitSettled { library.scanState.value is LibraryScanState.Finished }

        assertTrue(library.publications.value.any { it.id == publicationId })
    }
}
