package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.ShelvesStore
import app.storyarc.core.persistence.SourceStore
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
    fun `a view model with no stores is left as it is`() {
        val library = LibraryViewModel(application)

        library.reloadAfterImport()

        assertTrue(library.registry.value.sources.isEmpty())
        assertTrue(library.shelves.value.collections.isEmpty())
    }
}
