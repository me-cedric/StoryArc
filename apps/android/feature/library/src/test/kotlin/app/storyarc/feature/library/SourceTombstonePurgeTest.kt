package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.SourceTombstone
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * 10.12 and 10.14: what happens around a source's tombstone, through the model that writes
 * and reads it. `SourceRegistryTest` covers the pure logic -- what a tombstone carries, and
 * how one is found again. These tests cover the two call sites that use it: removal, which
 * has to capture what the source held before the rows go, and re-adding, which has to find
 * the old tombstone before minting a new identifier.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceTombstonePurgeTest {

    private fun library(progressStore: ProgressStore? = null) =
        LibraryViewModel(ApplicationProvider.getApplicationContext<Application>(), progressStore = progressStore)

    private fun catalogue(name: String = "Comics", locator: String = "https://example.com/feed") =
        Source(displayName = name, kind = SourceKind.OPDS_CATALOG, state = SourceConnectionState.Connected, locator = locator)

    private fun publication(identity: PublicationIdentity, sourceId: UUID) = Publication(
        identity = identity,
        format = PublicationFormat.CBZ,
        displayTitle = "Comics 01",
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    // 10.12: removal captures what the source held

    @Test
    fun `removing a source carries the publications it held into the tombstone`() {
        val library = library()
        val source = catalogue()
        library.addSource(source)
        val identity = PublicationIdentity(normalizedPath = "/Comics/01.cbz")
        library._publications.value = listOf(publication(identity, source.id))

        library.removeSource(source, credentials = null)

        assertEquals(listOf(identity), library._registry.value.tombstones.first().identities)
    }

    // 10.14: re-adding finds the old tombstone

    @Test
    fun `re-adding the same catalogue restores its old identifier and clears the tombstone`() {
        val library = library()
        val original = catalogue()
        library.addSource(original)
        library.removeSource(original, credentials = null)
        assertTrue(library._registry.value.tombstones.isNotEmpty())

        val fresh = catalogue()
        library.addSource(fresh)

        assertEquals(original.id.let { library._registry.value[it] }?.id, original.id)
        assertNull(library._registry.value[fresh.id])
        assertTrue(library._registry.value.tombstones.isEmpty())
    }

    @Test
    fun `adding an unrelated catalogue does not take over another source's tombstone`() {
        val library = library()
        val original = catalogue(name = "Comics", locator = "https://example.com/feed")
        library.addSource(original)
        library.removeSource(original, credentials = null)

        val unrelated = catalogue(name = "Manga", locator = "https://other.example/feed")
        library.addSource(unrelated)

        assertEquals(unrelated.id, library._registry.value[unrelated.id]?.id)
        assertTrue(library._registry.value.tombstones.any { it.sourceId == original.id })
    }

    // 10.12: the purge itself

    @Test
    fun `purging an expired tombstone forgets the position of a book nothing else holds`() = runTest {
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val library = library(progress)
        val source = catalogue()
        library.addSource(source)
        val identity = PublicationIdentity(normalizedPath = "/Comics/01.cbz")
        library._publications.value = listOf(publication(identity, source.id))
        progress.save(ReadingProgress(identity = identity, position = ReadingPosition.Page(3, 10), updatedAtEpochMillis = 0))

        library.removeSource(source, credentials = null)
        library._publications.value = emptyList()

        library.purgeExpiredTombstones(System.currentTimeMillis() + SourceTombstone.RETENTION_MILLIS + 1)

        assertNull(progress.progress(identity))
        assertTrue(library._registry.value.tombstones.isEmpty())
    }

    @Test
    fun `purging an expired tombstone keeps the position of a book another source still holds`() = runTest {
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val library = library(progress)
        val source = catalogue()
        library.addSource(source)
        val identity = PublicationIdentity(normalizedPath = "/Comics/01.cbz")
        library._publications.value = listOf(publication(identity, source.id))
        progress.save(ReadingProgress(identity = identity, position = ReadingPosition.Page(3, 10), updatedAtEpochMillis = 0))

        library.removeSource(source, credentials = null)
        // Another source still has the same book on the shelf -- a folder copy, say.
        library._publications.value = listOf(publication(identity, UUID.randomUUID()))

        library.purgeExpiredTombstones(System.currentTimeMillis() + SourceTombstone.RETENTION_MILLIS + 1)

        assertEquals(identity, progress.progress(identity)?.identity)
    }

    @Test
    fun `purging before the thirty days are up forgets nothing`() = runTest {
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val library = library(progress)
        val source = catalogue()
        library.addSource(source)
        val identity = PublicationIdentity(normalizedPath = "/Comics/01.cbz")
        library._publications.value = listOf(publication(identity, source.id))
        progress.save(ReadingProgress(identity = identity, position = ReadingPosition.Page(3, 10), updatedAtEpochMillis = 0))

        library.removeSource(source, credentials = null)
        library._publications.value = emptyList()

        library.purgeExpiredTombstones(0)

        assertEquals(identity, progress.progress(identity)?.identity)
        assertTrue(library._registry.value.tombstones.isNotEmpty())
    }
}
