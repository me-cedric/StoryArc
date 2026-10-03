package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.SourceReadProgressStore
import app.storyarc.core.persistence.StoredSourceProgress
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A source already mid-continuation resumes from [SourceReadProgressStore], not from page
 * two.
 *
 * `sources`' *More from a source than the library holds*: before this store existed,
 * [LibraryViewModel.partialSources] held the only copy of where a continuation stood, so a
 * relaunch forgot it. [LibraryViewModel.adoptPartialSources] is the one place a fresh
 * continuation and a resumed one both get seeded, and this is where that seam is tested.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaContinuationResumesFromDiskTest {

    private val app get() = ApplicationProvider.getApplicationContext<Application>()

    @Test
    fun `a source already mid-continuation resumes from disk instead of restarting at page two`() {
        val sourceId = UUID.randomUUID()
        SourceReadProgressStore.open(app)
            .record(sourceId, StoredSourceProgress(read = 120, total = 215, nextPage = 3))

        val library = LibraryViewModel(app)
        library.adoptPartialSources(setOf(sourceId))

        assertEquals(SourceReadProgress(read = 120, total = 215, nextPage = 3), library.partialSources[sourceId])
    }

    @Test
    fun `a source with nothing recorded starts from its first slice, as before`() {
        val sourceId = UUID.randomUUID()

        val library = LibraryViewModel(app)
        library.adoptPartialSources(setOf(sourceId))

        // Not a registered source of any kind here, so its first slice is zero -- the same
        // answer `firstSliceFor` gives any source it cannot find, unmoved by this change.
        assertEquals(SourceReadProgress.started(firstSliceRead = 0), library.partialSources[sourceId])
    }

    @Test
    fun `a source that stops being partial is forgotten on disk, not only in memory`() {
        val sourceId = UUID.randomUUID()
        val store = SourceReadProgressStore.open(app)
        store.record(sourceId, StoredSourceProgress(read = 60, total = null, nextPage = 2))
        val library = LibraryViewModel(app)
        library.adoptPartialSources(setOf(sourceId))

        library.adoptPartialSources(emptySet())

        assertNull(store.progress(sourceId))
        assertNull(library.partialSources[sourceId])
    }
}
