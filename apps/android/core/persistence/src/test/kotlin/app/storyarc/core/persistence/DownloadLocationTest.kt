package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a download is written where a removal will look for it.
 *
 * The defect this pins: the queue named the file after the publication and the Settings
 * screen deleted the one named after the identifier, so removing a download dropped the
 * record, left the bytes, and the storage total on that same screen never went down.
 *
 * Mirrors iOS's `DownloadLocationTests`.
 */
class DownloadLocationTest {

    private val directory = File(System.getProperty("java.io.tmpdir"), "downloads-${System.nanoTime()}")

    private fun store() = DownloadStore(FakePreferences(), directory)

    private fun download(id: String = "urn:storyarc:6", title: String = "Bone 6") = Download(
        id = id,
        title = title,
        remote = "https://example.test/$id",
        mediaType = "application/vnd.comicbook+zip",
        state = Download.State.Finished,
        downloadedBytes = 3,
    )

    @After
    fun tearDown() {
        directory.deleteRecursively()
    }

    @Test
    fun `the path a download is written to is the path it is looked for at`() {
        val store = store()
        val download = download()

        assertEquals(
            store.location(download),
            store.location(download.id, download.mediaType, download.title),
        )
    }

    @Test
    fun `the file is named after the publication, not after its identifier`() {
        val store = store()

        // A reader recognises "Bone 6"; nobody recognises `urn-storyarc-6`. The indexer also
        // reads a title and a series back out of the filename.
        assertEquals("Bone 6.cbz", store.location(download()).name)
    }

    @Test
    fun `removing takes the bytes, whatever the file inside happened to be called`() {
        val store = store()
        val download = download()

        // Written the way a build before this one wrote it: under the identifier.
        val old = store.location(download.id, download.mediaType, download.id)
        store.prepare(old)
        old.writeBytes(byteArrayOf(1, 2, 3))
        assertTrue(old.exists())

        assertTrue(store.remove(download))
        assertFalse("bytes under an older naming are gone too", old.exists())
        assertFalse(store.location(download).exists())
    }

    @Test
    fun `a title a filesystem would refuse is made safe without colliding with the identity`() {
        val store = store()
        val awkward = download(title = "Bone: Out/From \"Boneville\"")

        val file = store.location(awkward)
        assertFalse(file.name.contains('/'))
        assertEquals(store.location(awkward).parentFile, file.parentFile)
    }

    @Test
    fun `a download with no title falls back to its identity rather than to nothing`() {
        val store = store()

        assertEquals("urn-storyarc-6.cbz", store.location(download(title = "  ")).name)
    }

    // A catalogue names the directory, so a catalogue can try to escape it.
    // Mirrors iOS's `dotsCannotEscape` / `removeCannotReachOutside`, case for case.

    @Test
    fun `an id of dots alone cannot name the directory above`() {
        val store = store()
        for (hostile in listOf("..", ".", "...", ".....")) {
            val file = store.location(download(id = hostile))
            // The download's own directory, not its parent. An OPDS feed supplies the id
            // verbatim, so this is the one place that can refuse a hostile one.
            assertFalse(hostile, file.path.contains("${File.separator}..${File.separator}"))
            assertTrue(hostile, file.canonicalPath.startsWith(directory.canonicalPath + File.separator))
        }
    }

    @Test
    fun `removing a download named dot dot leaves everything above it alone`() {
        val store = store()
        directory.mkdirs()
        // A sibling of the downloads directory, which nothing about this download owns.
        val sibling = File(directory.parentFile, "elsewhere-${System.nanoTime()}")
        sibling.mkdirs()
        val bystander = File(sibling, "progress.db")
        bystander.writeText("reading progress")
        try {
            store.remove(download(id = ".."))

            assertTrue(bystander.exists())
            assertTrue(directory.exists())
        } finally {
            sibling.deleteRecursively()
        }
    }
}
