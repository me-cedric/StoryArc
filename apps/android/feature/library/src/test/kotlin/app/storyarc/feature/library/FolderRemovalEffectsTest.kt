package app.storyarc.feature.library

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 10.11 and 10.13: what removing or replacing a folder source takes with it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FolderRemovalEffectsTest {

    private fun library() = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())

    private fun publication(title: String, sourceId: java.util.UUID?) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    private fun folder(
        locator: String,
        state: SourceConnectionState = SourceConnectionState.Connected,
        name: String = locator.substringAfterLast('/'),
    ) = Source(displayName = name, kind = SourceKind.LOCAL_FOLDER, locator = locator).copy(state = state)

    @Test
    fun `removing a folder source takes its rows off the shelf`() {
        val library = library()
        val tree = Uri.parse("content://com.example.documents/tree/Comics")
        val source = folder(tree.toString())
        library._registry.value = SourceRegistry(sources = listOf(source))
        library._publications.value = listOf(publication("Kept", source.id), publication("Other", null))
        library._folders.value = listOf(tree)
        library.resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        library.removeFolder(tree)

        assertEquals(listOf("Other"), library._publications.value.map { it.displayTitle })
        assertNull(library._registry.value[source.id])
        assertTrue(library.resolver.persistedUriPermissions.none { it.uri == tree })
    }

    @Test
    fun `removing an unreachable folder source releases its grant and takes its rows`() {
        val library = library()
        val tree = Uri.parse("content://com.example.documents/tree/Gone")
        val source = folder(tree.toString(), SourceConnectionState.Unreachable(0))
        library._registry.value = SourceRegistry(sources = listOf(source))
        library._publications.value = listOf(publication("Orphaned", source.id))
        // Not in `_folders`: this is exactly the unreachable case, where the tree the reader
        // picked is no longer one `removeFolder`'s own lookup can find. The system still
        // holds the grant, which is what `removeSource` has to give back on this path.
        library._folders.value = emptyList()
        library.resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        library.removeSource(source, credentials = null)

        assertNull(library._registry.value[source.id])
        assertTrue(library._publications.value.none { it.sourceId == source.id })
        assertTrue(library.resolver.persistedUriPermissions.none { it.uri == tree })
    }

    @Test
    fun `a re-pick under the same name retires the stale unreachable row it replaces`() {
        val library = library()
        val staleTree = Uri.parse("content://old-provider/tree/Comics")
        val stale = folder(staleTree.toString(), SourceConnectionState.Unreachable(0))
        library._registry.value = SourceRegistry(sources = listOf(stale))
        library._publications.value = listOf(publication("Orphaned", stale.id))
        library.resolver.takePersistableUriPermission(staleTree, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        library.retireStaleFolderRows("Comics", "content://new-provider/tree/Comics")

        assertNull(library._registry.value[stale.id])
        assertTrue(library._publications.value.none { it.sourceId == stale.id })
        assertTrue(library.resolver.persistedUriPermissions.none { it.uri == staleTree })
    }

    @Test
    fun `a still-reachable folder of the same name is left alone`() {
        val library = library()
        val reachable = folder("content://provider/tree/Comics", SourceConnectionState.Connected)
        library._registry.value = SourceRegistry(sources = listOf(reachable))

        library.retireStaleFolderRows("Comics", "content://new-provider/tree/Comics")

        assertEquals(reachable, library._registry.value[reachable.id])
    }

    @Test
    fun `an unreachable folder of a different name is left alone`() {
        val library = library()
        val unrelated = folder("content://provider/tree/Manga", SourceConnectionState.Unreachable(0))
        library._registry.value = SourceRegistry(sources = listOf(unrelated))

        library.retireStaleFolderRows("Comics", "content://new-provider/tree/Comics")

        assertEquals(unrelated, library._registry.value[unrelated.id])
    }
}
