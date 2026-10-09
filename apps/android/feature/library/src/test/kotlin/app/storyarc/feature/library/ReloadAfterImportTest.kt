package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
import kotlinx.coroutines.flow.update
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `library-portability` / *Import merges*: an import writes the stores, and the view model that
 * holds copies of two of them re-reads them. Without this a reader sees an imported library only
 * after the next launch. iOS's `LibraryModelImportTests` asserts the same row.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReloadAfterImportTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `the sources and the shelves an import wrote appear`() {
        val sourceStore = SourceStore.open(application)
        val shelvesStore = ShelvesStore.open(application)
        val library = LibraryViewModel(application, sourceStore = sourceStore, shelvesStore = shelvesStore)
        assertTrue(library.registry.value.sources.isEmpty())
        assertTrue(library.shelves.value.collections.isEmpty())

        // What `LibraryArchive.apply` does to the two stores.
        sourceStore.save(
            SourceRegistry(
                sources = listOf(
                    Source(displayName = "Comics NAS", kind = SourceKind.NETWORK_SHARE, locator = "smb://nas.local/comics"),
                ),
            ),
        )
        shelvesStore.save(Shelves(collections = listOf(PublicationCollection(name = "Image Comics"))))
        assertTrue(library.registry.value.sources.isEmpty())

        library.reloadAfterImport()

        assertEquals(listOf("Comics NAS"), library.registry.value.sources.map { it.displayName })
        assertEquals(listOf("Image Comics"), library.shelves.value.collections.map { it.name })
    }

    @Test
    fun `library sync task 5_7 - a source that answered keeps its state through the reload`() {
        val sourceStore = SourceStore.open(application)
        val share = Source(displayName = "Sync share", kind = SourceKind.NETWORK_SHARE, locator = "smb://nas.local/sync")
        val other = Source(displayName = "Comics", kind = SourceKind.OPDS_CATALOG, locator = "https://opds.local")
        sourceStore.save(SourceRegistry(sources = listOf(share, other)))
        val library = LibraryViewModel(application, sourceStore = sourceStore)
        library._registry.update {
            it.marking(share.id, SourceConnectionState.Connected).marking(other.id, SourceConnectionState.Unreachable(7))
        }
        val arriving = Source(displayName = "From the sync", kind = SourceKind.KAVITA_SERVER, locator = "https://kavita.local")
        sourceStore.save(SourceRegistry(sources = listOf(share, other, arriving)))

        library.reloadAfterImport()

        val states = library.registry.value.sources.associate { it.displayName to it.state }
        assertEquals(SourceConnectionState.Connected, states["Sync share"])
        assertEquals(SourceConnectionState.Unreachable(7), states["Comics"])
        assertEquals(SourceConnectionState.Connecting, states["From the sync"])
    }

    @Test
    fun `a view model with no stores is left as it is`() {
        val library = LibraryViewModel(application)

        library.reloadAfterImport()

        assertTrue(library.registry.value.sources.isEmpty())
        assertTrue(library.shelves.value.collections.isEmpty())
    }
}
