package app.storyarc.core.format

import app.storyarc.core.model.ChosenCover
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.coverOverrideKey
import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-portability` task 6.7: an export has to name the covers a reader chose, and the
 * store files them under a hash. These are the rows that make the name recoverable. iOS's
 * `CoverOverrideKeyTests` is the twin.
 */
class CoverOverrideKeyTest {

    private fun folder(): File = createTempDirectory("cover-keys").toFile()

    private fun publication(digest: String?, path: String) = Publication(
        identity = PublicationIdentity(contentDigest = digest, normalizedPath = path),
        format = PublicationFormat.CBZ,
        displayTitle = path,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `a cover filed by key is named, with its image, by a store that never saw the publication`() {
        val directory = folder()
        CoverOverrideStore(directory).store("sha:d1", byteArrayOf(7, 7))

        val chosen = CoverOverrideStore(directory).chosen(emptyList())

        assertEquals(listOf(ChosenCover("sha:d1", byteArrayOf(7, 7))), chosen)
    }

    @Test
    fun `a cover chosen through the publication API is named by the same key an export uses`() {
        val directory = folder()
        val store = CoverOverrideStore(directory)
        val book = publication("d1", "/a.cbz")

        store.store(byteArrayOf(1), book)

        assertEquals(listOf(book.identity.coverOverrideKey), store.chosen(emptyList()).map { it.key })
        assertArrayEquals(byteArrayOf(1), store.image("sha:d1"))
        assertArrayEquals(byteArrayOf(1), store.bytes(book))
    }

    @Test
    fun `a cover chosen before keys were filed is found when its key is a candidate`() {
        val directory = folder()
        val store = CoverOverrideStore(directory)
        store.store("sha:old", byteArrayOf(9))
        directory.listFiles { file -> file.extension == "key" }!!.forEach { it.delete() }

        assertTrue(store.chosen(emptyList()).isEmpty())
        assertEquals(
            listOf("sha:old"),
            store.chosen(listOf("sha:old", "sha:never-chosen")).map { it.key },
        )
    }

    @Test
    fun `removing a cover removes its image and the file that names it`() {
        val directory = folder()
        val store = CoverOverrideStore(directory)
        store.store("sha:d1", byteArrayOf(1))

        store.remove("sha:d1")

        assertTrue(store.chosen(emptyList()).isEmpty())
        assertTrue(directory.listFiles()!!.isEmpty())
    }
}
