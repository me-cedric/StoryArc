package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Removing a finished publication's download, reversibly.
 *
 * `offline-downloads`: the download is removed, "its progress is kept, and the removal is
 * undoable for 10 seconds". Undoable is the part worth testing: a file already deleted can
 * only be put back by downloading it again, which is not an undo.
 */
class FinishedCleanupTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun store(): DownloadStore =
        DownloadStore(FakePreferences(), folder.newFolder("downloads"))

    private fun libraryWith(store: DownloadStore, id: String): DownloadLibrary {
        val download = Download(
            id = id,
            title = id,
            remote = "https://example.test/$id",
            mediaType = "application/vnd.comicbook+zip",
            state = Download.State.Finished,
            downloadedBytes = 3,
        )
        val file = store.location(id, "cbz", download.title)
        // The id is a directory now, so the fixture makes it like the queue does.
        store.prepare(file)
        file.writeBytes(byteArrayOf(1, 2, 3))
        return DownloadLibrary(downloads = listOf(download))
    }

    @Test
    fun `finds the download whose file the reader finished`() = runBlocking {
        val store = store()
        val library = libraryWith(store, "one")
        val found = finishedDownload(store, library) { it.endsWith("one.cbz") }
        assertEquals("one", found?.id)
    }

    @Test
    fun `finds nothing when the reader has finished nothing`() = runBlocking {
        val store = store()
        assertNull(finishedDownload(store, libraryWith(store, "one")) { false })
    }

    @Test
    fun `the bytes wait rather than going, so the removal can be undone`() = runBlocking {
        val store = store()
        val library = libraryWith(store, "one")
        val home = store.location("one", "cbz", "one")

        val (without, removed) = requireNotNull(removeAfterFinishing(store, library, "one"))
        assertNull(without["one"])
        assertFalse("the file is out of the way", home.exists())
        assertTrue("but it has not been deleted", removed.aside.exists())

        val restored = removed.undo(without)
        assertEquals("one", restored["one"]?.id)
        assertTrue("and it is back where it was", home.exists())
        assertEquals(3, home.length())
    }

    @Test
    fun `settling lets the bytes go`() = runBlocking {
        val store = store()
        val library = libraryWith(store, "one")
        val (_, removed) = requireNotNull(removeAfterFinishing(store, library, "one"))
        removed.settle()
        assertFalse(removed.aside.exists())
    }

    @Test
    fun `a download with no file on disk is left alone`() = runBlocking {
        val store = store()
        val library = libraryWith(store, "one")
        store.location("one", "cbz", "one").delete()
        assertNull(removeAfterFinishing(store, library, "one"))
    }
}
