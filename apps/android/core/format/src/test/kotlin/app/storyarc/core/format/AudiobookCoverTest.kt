package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory

/**
 * The JVM half of an audiobook's own cover: a folder's loose image, and where embedded
 * artwork is written once it is read out.
 *
 * `MediaMetadataRetriever.getEmbeddedPicture()` itself is a framework stub on a host JVM —
 * asserted instead in `AudiobookCoverInstrumentedTest`, the same split `CoverLoaderTest` and
 * `CoverLoaderInstrumentedTest` already draw for decoding a `Bitmap`.
 */
class AudiobookCoverTest {

    // MARK: - A folder's own loose cover

    @Test
    fun `a folder's own cover-png is found beside its tracks`() {
        val found = AudiobookCover.inFolder(FixtureCorpus.file("audiobooks/mixed-folder"))
        assertEquals("cover.png", found?.name)
    }

    @Test
    fun `a folder with no loose cover names none`() {
        val found = AudiobookCover.inFolder(FixtureCorpus.file("audiobooks/folder-parts"))
        assertNull(found)
    }

    @Test
    fun `the first matching name wins, in the declared order`() {
        val folder = createTempDirectory("audiobook-cover-names").toFile()
        try {
            File(folder, "folder.png").writeBytes(byteArrayOf(1))
            File(folder, "cover.jpg").writeBytes(byteArrayOf(2))

            val found = AudiobookCover.inFolder(folder)

            assertEquals("cover.jpg", found?.name)
        } finally {
            folder.deleteRecursively()
        }
    }

    // MARK: - Indexing a folder's own cover

    @Test
    fun `a folder of audio indexes its own loose cover`() = runTest {
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/mixed-folder"))
        assertEquals(
            FixtureCorpus.file("audiobooks/mixed-folder/cover.png").path,
            publication.coverPath,
        )
    }

    @Test
    fun `a folder of audio with no loose cover indexes none`() = runTest {
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/folder-parts"))
        assertNull(publication.coverPath)
    }

    // MARK: - The store

    @Test
    fun `written artwork is read back byte for byte`() {
        val directory = createTempDirectory("audiobook-cover-store").toFile()
        try {
            val store = AudiobookCoverStore(directory)
            val source = File("/library/audiobooks/with-cover.m4b")
            val data = byteArrayOf(1, 2, 3, 4, 5)

            val path = store.write(data, source)

            assertEquals(data.toList(), path?.let { File(it).readBytes().toList() })
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `writing the same source twice replaces rather than accumulates`() {
        val directory = createTempDirectory("audiobook-cover-store").toFile()
        try {
            val store = AudiobookCoverStore(directory)
            val source = File("/library/audiobooks/with-cover.m4b")

            val first = store.write(byteArrayOf(1), source)
            val second = store.write(byteArrayOf(2), source)

            assertEquals(first, second)
            assertEquals(listOf<Byte>(2), second?.let { File(it).readBytes().toList() })
            assertEquals(1, directory.listFiles()?.size)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `two different sources are written to two different files`() {
        val directory = createTempDirectory("audiobook-cover-store").toFile()
        try {
            val store = AudiobookCoverStore(directory)

            val a = store.write(byteArrayOf(1), File("/library/audiobooks/a.m4b"))
            val b = store.write(byteArrayOf(2), File("/library/audiobooks/b.m4b"))

            assert(a != b)
            assertEquals(2, directory.listFiles()?.size)
        } finally {
            directory.deleteRecursively()
        }
    }
}
