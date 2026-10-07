package app.storyarc.feature.epubreader

import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.format.RandomAccessSource
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.util.getOrElse
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Random
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * A reflowable EPUB on a share streams: Readium reads it through [SourceResource], and the
 * bytes the source hands out are counted (close-the-audited-gaps 14.15).
 *
 * The book is the corpus's `fixture.epub` with 12 MB of incompressible bytes added as an entry
 * no chapter names. Readium reads the whole of a ZIP under 5 MB into memory, so a smaller book
 * could not tell streaming from a whole fetch. iOS's `EpubStreamingTests` builds the same book.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class EpubStreamingTest {

    @Test
    fun `a reflowable EPUB on a share opens and reads a chapter without the whole file`() = runBlocking {
        val bytes = paddedFixture()
        val source = CountingSource(bytes)
        PublicationAccess.register(SCHEME) { source }

        val opening = openEpub(RuntimeEnvironment.getApplication(), "$SCHEME://nas/books/fixture.epub")

        val publication = (opening as? EpubOpening.Opened)?.publication
            ?: error("the streamed EPUB did not open: $opening")
        val chapter = publication.get(publication.readingOrder.first())
            ?.read()?.getOrElse { error("the first chapter did not read: $it") }
            ?: error("the first chapter is missing")
        assertTrue(String(chapter).contains("<html", ignoreCase = true))
        assertEquals(2, publication.readingOrder.size)
        assertTrue(
            "Readium read ${source.bytesRead} of ${bytes.size} bytes to open one chapter",
            source.bytesRead < bytes.size / 4,
        )
    }

    @Test
    fun `a share that cannot be reached is stated as unreachable`() = runBlocking {
        PublicationAccess.register(SCHEME) { error("the share dropped the connection") }

        val opening = openEpub(RuntimeEnvironment.getApplication(), "$SCHEME://nas/books/fixture.epub")

        assertEquals(EpubOpening.Unreachable, opening)
    }

    private fun paddedFixture(): ByteArray {
        val fixture = File(
            System.getProperty("storyarc.epubreader.projectDir"),
            "../../../../packages/test-fixtures/ebooks/fixture.epub",
        )
        val out = ByteArrayOutputStream()
        ZipFile(fixture).use { zip ->
            ZipOutputStream(out).use { writer ->
                for (entry in zip.entries()) {
                    writer.putNextEntry(ZipEntry(entry.name).apply { method = entry.method; copySizes(entry) })
                    zip.getInputStream(entry).use { it.copyTo(writer) }
                    writer.closeEntry()
                    if (entry.name == "mimetype") {
                        writer.putNextEntry(ZipEntry("OEBPS/unreferenced.bin"))
                        writer.write(ByteArray(PADDING).also { Random(7).nextBytes(it) })
                        writer.closeEntry()
                    }
                }
            }
        }
        return out.toByteArray()
    }

    private fun ZipEntry.copySizes(from: ZipEntry) {
        if (from.method == ZipEntry.STORED) {
            size = from.size
            compressedSize = from.compressedSize
            crc = from.crc
        }
    }

    private class CountingSource(private val data: ByteArray) : RandomAccessSource {
        @Volatile
        var bytesRead = 0L

        override val length: Long = data.size.toLong()

        override suspend fun read(offset: Long, count: Int): ByteArray {
            val end = minOf(offset.toInt() + count, data.size)
            synchronized(this) { bytesRead += end - offset }
            return data.copyOfRange(offset.toInt(), end)
        }
    }

    private companion object {
        const val SCHEME = "storyarc-epub-test"
        const val PADDING = 12 * 1024 * 1024
    }
}
