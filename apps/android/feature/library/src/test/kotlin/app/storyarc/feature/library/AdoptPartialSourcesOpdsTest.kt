package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 22.1-smb-opds: seeding [LibraryViewModel.opdsNext] for a catalogue that just turned
 * partial, and leaving it alone on every call after -- the same "keeps its progress" rule
 * `KavitaContinuedRead.adoptPartialSources`'s own doc comment states for Kavita's page
 * number, asked here of a catalogue's feed link instead.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AdoptPartialSourcesOpdsTest {

    private val sourceId = UUID.randomUUID()

    private fun library(): LibraryViewModel {
        val library = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
        library.addSource(Source(id = sourceId, displayName = "Library", kind = SourceKind.OPDS_CATALOG))
        return library
    }

    @Test
    fun `a catalogue that just turned partial is seeded with the next link its first page found`() {
        val library = library()

        library.adoptPartialSources(setOf(sourceId), mapOf(sourceId to "https://library.example/feed?page=2"), pins = CertificatePins())

        assertEquals(SourceReadProgress.started(firstSliceRead = 0), library.readProgress(sourceId))
        assertEquals("https://library.example/feed?page=2", library.opdsNext[sourceId])
    }

    @Test
    fun `a catalogue already mid-continuation keeps its link, not a fresh one`() {
        val library = library()
        library.adoptPartialSources(setOf(sourceId), mapOf(sourceId to "https://library.example/feed?page=2"), pins = CertificatePins())
        library.opdsNext = library.opdsNext + (sourceId to "https://library.example/feed?page=5")

        // A second `readServers()` pull reads the catalogue's root again and hands back its
        // own "page=2" -- the same link every pull-to-refresh answers, because the root feed
        // never knows how far a continuation already got.
        library.adoptPartialSources(setOf(sourceId), mapOf(sourceId to "https://library.example/feed?page=2"), pins = CertificatePins())

        // The bug this guards: seeding unconditionally would stamp "page=2" back over the
        // continuation's own "page=5" on every pull, so it could never advance past its
        // second page. Mutate `adoptPartialSources`'s `if (partialSources[sourceId] == null)`
        // guard away and this fails.
        assertEquals("https://library.example/feed?page=5", library.opdsNext[sourceId])
    }

    @Test
    fun `a catalogue that finished its read loses its link too`() {
        val library = library()
        library.adoptPartialSources(setOf(sourceId), mapOf(sourceId to "https://library.example/feed?page=2"), pins = CertificatePins())

        library.adoptPartialSources(emptySet(), emptyMap(), pins = CertificatePins())

        assertNull(library.readProgress(sourceId))
        assertNull(library.opdsNext[sourceId])
    }
}
