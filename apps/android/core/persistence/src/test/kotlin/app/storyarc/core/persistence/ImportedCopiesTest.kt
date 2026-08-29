package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Copying a publication into storage the app owns.
 *
 * `local-library`: an imported file "is copied into app storage, indexed, and listed under
 * an 'On this device' source", and the copy "survives the original being moved or deleted".
 * The indexing and the listing are the library's; the copy, the record and the promise that
 * the two agree are this store's. iOS's `ImportedCopiesTests` asserts the same cases.
 */
class ImportedCopiesTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun store(): DownloadStore =
        DownloadStore(FakePreferences(), folder.newFolder("downloads"))

    /** An original somewhere else on the device, which the copy has to outlive. */
    private fun original(name: String = "Bone 01.cbz", bytes: Int = 512): File {
        val elsewhere = folder.newFolder("elsewhere-${name.hashCode()}")
        return File(elsewhere, name).apply { writeBytes(ByteArray(bytes)) }
    }

    private fun DownloadStore.import(file: File, library: DownloadLibrary = DownloadLibrary()) =
        importing(file.name, file.absolutePath, library) { file.inputStream() }

    @Test
    fun `an imported file is copied into app storage and recorded`() {
        val store = store()
        val copy = store.import(original())

        assertTrue("the copy is on disk", copy.file.exists())
        assertEquals(ImportedCopies.SOURCE_ID, copy.download.sourceId)
        assertEquals(Download.State.Finished, copy.download.state)
        assertEquals(512L, copy.bytes)
        // The reader's own name for the book, not its identifier: the indexer reads a title
        // and a series out of a filename, so the copy has to keep one.
        assertEquals("Bone 01.cbz", copy.file.name)
    }

    @Test
    fun `the record and the file agree about where the copy is`() {
        // The store chose the path when it wrote the file and has to choose the same one to
        // find it again -- which is only true if the media type round-trips to an extension.
        val store = store()
        val copy = store.import(original("Maus.epub"))
        assertEquals(copy.file, store.locationOf(copy.download))
    }

    @Test
    fun `the copy outlives the original`() {
        val store = store()
        val file = original()
        val copy = store.import(file)

        assertTrue("the original goes", file.delete())
        assertTrue("the copy stays", copy.file.exists())
        assertEquals(copy.download.id, store.library()[copy.download.id]?.id)
    }

    @Test
    fun `importing the same file twice is one copy`() {
        // A reader who taps Import on a comic they imported last week gets the copy they
        // already have, not a second one beside it weighing the same.
        val store = store()
        val file = original()
        val first = store.import(file)
        val second = store.import(file, first.library)

        assertEquals(1, second.library.downloads.size)
        assertEquals(first.download.id, second.download.id)
        assertEquals(first.file, second.file)
    }

    @Test
    fun `a format StoryArc does not read is refused by name`() {
        // `local-library` forbids a generic failure. A reader who picked the wrong file has
        // no way to tell that from a broken app unless the app says which it is.
        val refusal = runCatching { store().import(original("notes.txt")) }.exceptionOrNull()
        assertEquals("TXT", (refusal as? ImportedCopies.ImportException.Unsupported)?.format)
    }

    @Test
    fun `what the copies weigh is counted from the disk`() {
        // `local-library` asks the app to report the space used, and a total taken from the
        // record would claim bytes the system may already have reclaimed.
        val store = store()
        store.import(original(bytes = 900))
        assertEquals(900L, store.bytesOnDisk())
    }

    @Test
    fun `an imported copy is never swept away by finishing it`() = runBlocking {
        // `offline-downloads` removes a finished download because the catalogue can be asked
        // for it again. Nothing can be asked for an import, so removing one on the last page
        // would be the app breaking `local-library`'s own promise.
        val store = store()
        val copy = store.import(original())
        assertNull(finishedDownload(store, copy.library) { true })
    }

    @Test
    fun `a download is still swept away by finishing it`() = runBlocking {
        // The other half of the same guard: excluding imports must not have excluded
        // everything.
        val store = store()
        val fetched = Download(
            id = "urn:uuid:1",
            title = "Bone 02",
            remote = "https://example.test/bone-02.cbz",
            mediaType = "application/vnd.comicbook+zip",
            state = Download.State.Finished,
        )
        val library = DownloadLibrary(downloads = listOf(fetched))
        assertEquals("urn:uuid:1", finishedDownload(store, library) { true }?.id)
    }

    @Test
    fun `the identity of a copy does not move with the original`() {
        // Keyed on the original's name and size rather than the `Uri` a provider handed over,
        // because the copy is promised to outlive the original being *moved* -- and a
        // provider gives the same file a different `Uri` every time it is opened.
        assertEquals(
            ImportedCopies.identity("Bone 01.cbz", 512),
            ImportedCopies.identity("Bone 01.cbz", 512),
        )
        assertNotEquals(
            ImportedCopies.identity("Bone 01.cbz", 512),
            ImportedCopies.identity("Bone 02.cbz", 512),
        )
    }
}
