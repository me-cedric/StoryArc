package app.storyarc.core.format

import app.storyarc.core.model.PublicationIdentity
import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Task 1.1's folder half: a loose cover inside a folder picked through the Storage Access
 * Framework.
 *
 * `AudiobookCover.inFolder` looks for a file beside the tracks, and a picked folder has no
 * files to look beside — `AudiobookFolder.of` builds one from a listing of names and sizes and
 * carries no root. So every audiobook folder a reader picked through the system picker drew a
 * glyph, even one holding `cover.jpg`. [LibraryScanner.looseCoverFrom] is the fix, and it is
 * lifted clear of the `ContentResolver` so this can assert it without a `DocumentsProvider`.
 */
class SafLooseCoverTest {

    @Test
    fun `a picked folder's own cover image is copied where the app can read it`() {
        val directory = temporaryFolder()
        val picture = byteArrayOf(0x42, 0x43, 0x44)

        val written = LibraryScanner.looseCoverFrom(
            entries = listOf(
                entry("1", "01 - Chapter One.mp3"),
                entry("2", "cover.jpg"),
                entry("3", "notes.txt"),
            ),
            key = "content://tree/primary%3ABooks/document/primary%3ABooks%2FThe%20Book",
            coverCacheDir = directory,
            read = { documentId -> picture.takeIf { documentId == "2" } },
        )

        assertEquals(picture.toList(), File(written!!).readBytes().toList())
        assertTrue(File(written).startsWith(directory))
    }

    @Test
    fun `a folder with no cover image among its names is left as it was`() {
        val written = LibraryScanner.looseCoverFrom(
            entries = listOf(entry("1", "01 - Chapter One.mp3"), entry("2", "notes.txt")),
            key = "content://tree/x",
            coverCacheDir = temporaryFolder(),
            read = { error("nothing should be read") },
        )

        assertNull(written)
    }

    @Test
    fun `a folder whose provider refuses the read is left as it was`() {
        val written = LibraryScanner.looseCoverFrom(
            entries = listOf(entry("2", "folder.png")),
            key = "content://tree/x",
            coverCacheDir = temporaryFolder(),
            read = { null },
        )

        assertNull(written)
    }

    @Test
    fun `a sub-folder named like a cover is not mistaken for one`() {
        val written = LibraryScanner.looseCoverFrom(
            entries = listOf(entry("2", "cover.jpg", isDirectory = true)),
            key = "content://tree/x",
            coverCacheDir = temporaryFolder(),
            read = { error("nothing should be read") },
        )

        assertNull(written)
    }

    @Test
    fun `two picked folders do not share one copy`() {
        val directory = temporaryFolder()
        val entries = listOf(entry("2", "cover.jpg"))
        val read = { _: String -> byteArrayOf(1) }

        val first = LibraryScanner.looseCoverFrom(entries, "content://tree/a", directory, read)
        val second = LibraryScanner.looseCoverFrom(entries, "content://tree/b", directory, read)

        assertTrue(first != second)
    }

    @Test
    fun `the copy the walk made becomes the folder's recorded cover`() {
        // The last link in the chain, and the one that is not about reading: a folder picked
        // through the system picker reaches `PublicationIndexer` as a list of names and sizes
        // with no root to look beside, so `AudiobookCover.inFolder` has nothing to answer and
        // the copy the walk made has to be carried in.
        val folder = AudiobookFolder.of(
            listOf(
                AudiobookFolder.Candidate("01 - One.mp3", 1024),
                AudiobookFolder.Candidate("02 - Two.mp3", 1024),
            ),
        )

        val publication = PublicationIndexer.index(
            folder,
            PublicationIdentity(normalizedPath = "content://tree/x"),
            "The Ridge Road",
            looseCover = "/data/user/0/app.storyarc/files/audio-covers/abc",
        )

        assertEquals("/data/user/0/app.storyarc/files/audio-covers/abc", publication.coverPath)
    }

    @Test
    fun `a picked folder the walk found no cover for records none`() {
        // The control. Without it a scanner that wrote the same path for every folder would
        // pass the case above.
        val folder = AudiobookFolder.of(listOf(AudiobookFolder.Candidate("01 - One.mp3", 1024)))

        val publication = PublicationIndexer.index(
            folder,
            PublicationIdentity(normalizedPath = "content://tree/x"),
            "The Ridge Road",
        )

        assertNull(publication.coverPath)
    }

    private fun entry(documentId: String, name: String, isDirectory: Boolean = false) =
        SafTree.Entry(documentId = documentId, name = name, isDirectory = isDirectory, size = 1)

    private fun temporaryFolder(): File =
        createTempDirectory("saf-loose-cover").toFile().also { it.deleteOnExit() }
}
