package app.storyarc.feature.library

import android.app.Application
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 10.15: a removed source's rows must not come back from the cached shelf at the next
 * launch. Neither `forget` nor `unregister` wrote the snapshot through, so the old cache put
 * the removed rows straight back on the shelf, and the launch scan (which never removes a
 * row of a source it did not walk) wrote them into the snapshot again -- they never went.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShelfWriteThroughTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private fun library() = LibraryViewModel(application)

    private fun publication(title: String, sourceId: java.util.UUID?) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    @Before
    fun setUp() {
        application.cacheDir.resolve("library.json").delete()
    }

    @After
    fun tearDown() {
        application.cacheDir.resolve("library.json").delete()
    }

    @Test
    fun `removing a server source writes the shelf through, so its row does not come back`() {
        val first = library()
        val server = Source(
            displayName = "Kavita",
            kind = SourceKind.KAVITA_SERVER,
            locator = "https://kavita.example",
        )
        first._registry.value = SourceRegistry(sources = listOf(server))
        first._publications.value = listOf(publication("Gone", server.id), publication("Kept", null))

        first.removeSource(server, credentials = null)

        val second = library()
        second.restoreCachedLibrary()

        assertEquals(listOf("Kept"), second.publications.value.map { it.displayTitle })
    }

    @Test
    fun `removing the only folder writes the emptied shelf through, so its row does not come back`() {
        val first = library()
        val tree = Uri.parse("content://com.example.documents/tree/Comics")
        val folder = Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER, locator = tree.toString())
        first._registry.value = SourceRegistry(sources = listOf(folder))
        first._publications.value = listOf(publication("Gone", folder.id))
        first._folders.value = listOf(tree)
        first.cacheLibrary()

        first.removeFolder(tree)

        val second = library()
        second.restoreCachedLibrary()

        assertTrue(second.publications.value.none { it.displayTitle == "Gone" })
    }
}
