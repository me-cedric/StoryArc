package app.storyarc.feature.library

import android.app.Application
import android.net.Uri
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

/**
 * 10.8: an import refusal names the detected format, the same way an open-in refusal does.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ImportFailureTest {

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

    private fun file(name: String, write: Boolean = true): Uri {
        val directory = File(application.cacheDir, "import-failure-${name.hashCode()}")
        directory.mkdirs()
        val file = File(directory, name)
        if (write) file.writeBytes("not really a comic".toByteArray())
        return Uri.fromFile(file)
    }

    private fun library() = LibraryViewModel(application, downloadStore = DownloadStore.open(application))

    /**
     * `importFile` launches in `viewModelScope` and hops to `Dispatchers.IO` for the real
     * read, which is a genuine background thread even under `UnconfinedTestDispatcher` --
     * so the test has to wait for it rather than read the result the instant the call
     * returns. Bounded, rather than a bare `Thread.sleep`, so a regression that never
     * completes fails in two seconds instead of hanging the suite.
     */
    private fun LibraryViewModel.awaitImportFailure(): ImportFailure? {
        val deadline = System.currentTimeMillis() + 2_000
        while (importFailure.value == null && System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        return importFailure.value
    }

    @Test
    fun `an unsupported format is named in the failure`() {
        val library = library()
        val uri = file("notes.txt")

        library.importFile(uri)
        val failure = library.awaitImportFailure()

        assertEquals("notes.txt", failure?.name)
        assertEquals("TXT", failure?.detected)
    }

    @Test
    fun `a file that cannot be read names no format, and nothing is imported`() {
        val library = library()
        val uri = file("missing.cbz", write = false)

        library.importFile(uri)
        val failure = library.awaitImportFailure()

        assertEquals("missing.cbz", failure?.name)
        assertNull(failure?.detected)
        assertTrue(library.publications.value.isEmpty())
    }
}
