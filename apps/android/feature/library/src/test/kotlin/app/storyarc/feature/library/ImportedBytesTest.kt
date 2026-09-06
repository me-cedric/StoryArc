package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.ImportedCopies
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * What the imported copies weigh, and who is told.
 *
 * `local-library`'s *Importing* scenario ends "**AND** the app reports the space used", and
 * `offline-downloads`' *Storage view* asks for the total "broken down by source". "On this
 * device" is a source, and [LibraryViewModel.importedBytes] is its share.
 *
 * **The accessor existed and nothing read it.** It was declared and referenced by no screen
 * and no test on either platform until the storage row was added, so the figure reached a
 * reader only inside the downloads total, under a label that says downloads.
 * [ImportedStorageRowTest] in `feature/settings` asserts the row that states it; this suite
 * asserts the number.
 *
 * iOS's `ImportedStorageTests` asserts the same four claims against `LibraryModel`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ImportedBytesTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        DownloadStore.open(application).save(DownloadLibrary())
    }

    /** A finished record, filed under the source the caller names. */
    private fun record(id: String, sourceId: UUID?, bytes: Long) = Download(
        id = id,
        sourceId = sourceId,
        title = id,
        remote = "file:///nowhere/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = Download.State.Finished,
        expectedBytes = bytes,
        downloadedBytes = bytes,
    )

    private fun store(vararg downloads: Download): DownloadStore =
        DownloadStore.open(application).apply { save(DownloadLibrary(downloads.toList())) }

    @Test
    fun `nothing imported weighs nothing`() = runTest {
        val model = LibraryViewModel(application, downloadStore = store())

        assertEquals(0L, model.importedBytes())
    }

    @Test
    fun `every imported copy is counted`() = runTest {
        val model = LibraryViewModel(
            application,
            downloadStore = store(
                record("one", ImportedCopies.SOURCE_ID, 512),
                record("two", ImportedCopies.SOURCE_ID, 1_024),
            ),
        )

        assertEquals(
            "The imported copies do not add up. This is the figure the storage row states," +
                " so a reader reads it beside the downloads total and subtracts one from" +
                " the other.",
            1_536L,
            model.importedBytes(),
        )
    }

    @Test
    fun `a download the app fetched is not counted as an imported copy`() = runTest {
        // The half that makes the row worth drawing. A figure that counted everything in the
        // downloads directory would be the total that is already on the screen above it.
        val model = LibraryViewModel(
            application,
            downloadStore = store(
                record("copy", ImportedCopies.SOURCE_ID, 512),
                record("fetched", UUID.randomUUID(), 4_096),
            ),
        )

        assertEquals(
            "A download the reader fetched from a source was counted as an imported copy." +
                " \"On this device\" is the source the copies are filed under, and a fetched" +
                " publication is filed under the source it came from.",
            512L,
            model.importedBytes(),
        )
    }

    @Test
    fun `a library with no download store reports nothing rather than refusing`() = runTest {
        // A storage figure is not worth a crash: the honest answer for an app that owns no
        // copies is that they weigh nothing.
        assertEquals(0L, LibraryViewModel(application).importedBytes())
    }
}
