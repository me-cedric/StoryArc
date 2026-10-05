package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
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
 * A share and a catalogue resume their continuation after a relaunch, which only a Kavita
 * server could do before.
 *
 * `sources`' *More from a source than the library holds* asks a read to keep going until the
 * library holds all of it, and a relaunch is the common case on a phone. Only Kavita wrote
 * its progress, so the resume branch [LibraryViewModel.adoptPartialSources] holds was dead
 * for the other two kinds. Neither continues by a page number, so the cursor has to be
 * written with the count or the restored record says where the read stood without saying
 * what to ask for next.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ContinuedReadCursorSurvivesRelaunchTest {

    private val sourceId = UUID.randomUUID()
    private val app get() = ApplicationProvider.getApplicationContext<Application>()

    private fun library(kind: SourceKind): LibraryViewModel {
        val library = LibraryViewModel(app)
        library.addSource(Source(id = sourceId, displayName = "Attic", kind = kind))
        return library
    }

    @Test
    fun `a share resumes the frontier it stopped at, not only the count it had reached`() {
        SourceReadProgressStore.open(app).record(
            sourceId,
            StoredSourceProgress(read = 540, total = null, nextPage = 4, smbQueue = listOf("d40", "d41")),
        )

        val library = library(SourceKind.NETWORK_SHARE)
        library.adoptPartialSources(setOf(sourceId))

        assertEquals(SourceReadProgress(read = 540, total = null, nextPage = 4), library.partialSources[sourceId])
        assertEquals(listOf("d40", "d41"), library.smbQueues[sourceId])
    }

    @Test
    fun `a catalogue resumes the link it stopped at, in preference to its first page's own`() {
        SourceReadProgressStore.open(app).record(
            sourceId,
            StoredSourceProgress(read = 180, total = null, nextPage = 7, opdsNext = "https://library.example/feed?page=7"),
        )

        val library = library(SourceKind.OPDS_CATALOG)
        // The root feed this launch just read hands back page two, as every pull does: it
        // has never heard of the six pages a previous launch already merged.
        library.adoptPartialSources(setOf(sourceId), mapOf(sourceId to "https://library.example/feed?page=2"))

        assertEquals(SourceReadProgress(read = 180, total = null, nextPage = 7), library.partialSources[sourceId])
        assertEquals("https://library.example/feed?page=7", library.opdsNext[sourceId])
    }

    @Test
    fun `a record written before the cursor was stored starts that share over`() {
        // What an older build left on disk: the count, and nothing to continue by. Resuming
        // it would ask page four for the share's root, adopt the rows the library already
        // holds, and report about twice the share's real size.
        SourceReadProgressStore.open(app).record(sourceId, StoredSourceProgress(read = 540, total = null, nextPage = 4))

        val library = library(SourceKind.NETWORK_SHARE)
        library.adoptPartialSources(setOf(sourceId))

        assertEquals(
            SourceReadProgress.started(firstSliceRead = SmbContributor.FIRST_SLICE),
            library.partialSources[sourceId],
        )
        assertNull(library.smbQueues[sourceId])
    }

    @Test
    fun `a landed continuation page writes its cursor to disk beside its count`() {
        val library = library(SourceKind.NETWORK_SHARE)
        library.partialSources = mapOf(sourceId to SourceReadProgress(read = 200, total = null, nextPage = 2))
        // `readSourceOnward` advances the cursor before it lands the page, so this is what
        // the map holds by the time `landContinuedSlice` runs.
        library.smbQueues = mapOf(sourceId to listOf("d40", "d41"))

        library.landContinuedSlice(
            sourceId,
            SourceSlice(publications = emptyList(), holdsMore = true),
            SourceReadStep.Continuing(SourceReadProgress(read = 540, total = null, nextPage = 3)),
        )

        assertEquals(
            StoredSourceProgress(read = 540, total = null, nextPage = 3, smbQueue = listOf("d40", "d41")),
            SourceReadProgressStore.open(app).progress(sourceId),
        )
    }

    @Test
    fun `a finished continuation forgets its cursor along with its count`() {
        val library = library(SourceKind.NETWORK_SHARE)
        library.partialSources = mapOf(sourceId to SourceReadProgress(read = 200, total = null, nextPage = 2))
        library.smbQueues = mapOf(sourceId to listOf("d40"))

        library.landContinuedSlice(
            sourceId,
            SourceSlice(publications = emptyList(), holdsMore = false),
            SourceReadStep.Finished(SourceReadProgress(read = 210, total = null, nextPage = 3)),
        )

        assertNull(SourceReadProgressStore.open(app).progress(sourceId))
    }
}
