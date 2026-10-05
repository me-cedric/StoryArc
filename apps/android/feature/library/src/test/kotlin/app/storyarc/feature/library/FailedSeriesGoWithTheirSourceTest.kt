package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.KavitaFailedSeriesStore
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A departed source takes its pending retries with it, and a source that merely finished its
 * read keeps them.
 *
 * [KavitaFailedSeriesStore.clear]'s own doc says it is "called when the source itself is
 * gone", and nothing called it: a reader who removed a Kavita server left its failed series
 * on disk for the life of the install. The prune loop in
 * [LibraryViewModel.adoptPartialSources] already drops a departed source's read progress, so
 * it is the one place that knows the difference between a source that is gone and a source
 * that is done.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FailedSeriesGoWithTheirSourceTest {

    private val sourceId = UUID.randomUUID()
    private val app get() = ApplicationProvider.getApplicationContext<Application>()

    @Test
    fun `a source the registry no longer holds loses its pending retries`() {
        val store = KavitaFailedSeriesStore.open(app)
        store.record(sourceId, setOf(5, 9))
        val library = LibraryViewModel(app)
        library.partialSources = mapOf(sourceId to SourceReadProgress.started(firstSliceRead = 0))

        // The read that follows a removal reports nothing partial for a source it can no
        // longer see, which is the same thing that happens when a read simply ends.
        library.adoptPartialSources(emptySet())

        assertTrue(store.pending(sourceId).isEmpty())
    }

    @Test
    fun `a source that merely finished its read keeps them`() {
        val store = KavitaFailedSeriesStore.open(app)
        store.record(sourceId, setOf(5, 9))
        val library = LibraryViewModel(app)
        library.addSource(Source(id = sourceId, displayName = "Attic", kind = SourceKind.KAVITA_SERVER))
        library.partialSources = mapOf(sourceId to SourceReadProgress.started(firstSliceRead = 0))

        library.adoptPartialSources(emptySet())

        // `retryFailedKavitaSeries` asks for these on every read after the continuation has
        // ended, which is the whole reason that function does not live inside the loop that
        // drives a partial source. Clearing here would make a failed series lost for good.
        assertEquals(setOf(5, 9), store.pending(sourceId))
    }
}
