package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Counts what a reader actually touches, so "ranged reads" can be asserted
 * rather than asserted-about.
 */
private class ReadCounter(private val inner: RandomAccessSource) : RandomAccessSource {
    var reads = 0
        private set
    var bytes = 0
        private set

    override val length: Long get() = inner.length

    override suspend fun read(offset: Long, count: Int): ByteArray {
        val data = inner.read(offset, count)
        reads++
        bytes += data.size
        return data
    }

    override fun close() = inner.close()
}

/**
 * iOS's `ZipReaderTests` mirrors this file. Both read the same corpus, so a
 * container bug on one platform and not the other shows up as a failing test
 * rather than as a user's page that will not open.
 */
class ZipReaderTest {
    private fun source(name: String) = FileSource(FixtureCorpus.file("comics/$name"))

    @Test
    fun `DEFLATE entries inflate to their recorded size`() = runTest {
        for (name in listOf("natural-sort.cbz", "zip64.cbz", "archive-comment.cbz", "data-descriptor.cbz")) {
            source(name).use { src ->
                val zip = ZipReader.open(src)
                val entry = zip.entries.first { PageOrdering.isPage(it.path) }
                val data = zip.data(entry)

                assertEquals("$name size", entry.uncompressedSize.toInt(), data.size)
                assertEquals("$name not a PNG — inflate produced junk", 0x89.toByte(), data[0])
                assertEquals('P'.code.toByte(), data[1])
            }
        }
    }

    @Test
    fun `STORED entries are returned as-is, not passed through inflate`() = runTest {
        source("stored-entries.cbz").use { src ->
            val zip = ZipReader.open(src)
            val entry = zip.entries.first()

            assertTrue(entry.isStored)
            val data = zip.data(entry)
            assertEquals(entry.uncompressedSize.toInt(), data.size)
            assertEquals(0x89.toByte(), data[0])
        }
    }

    @Test
    fun `Zip64 extended information is parsed`() = runTest {
        source("zip64.cbz").use { src ->
            val zip = ZipReader.open(src)

            assertEquals(3, zip.entries.size)
            // Every offset and size must still be sane after the 64-bit override.
            for (entry in zip.entries) {
                assertTrue(entry.localHeaderOffset >= 0)
                assertTrue(entry.uncompressedSize > 0)
            }
        }
    }

    @Test
    fun `an archive comment does not hide the EOCD`() = runTest {
        // The EOCD sits 646 bytes from the end of this fixture. A reader that
        // looks at a fixed tail offset instead of scanning for the signature
        // fails here, which is the whole reason the fixture exists.
        source("archive-comment.cbz").use { src ->
            val zip = ZipReader.open(src)

            assertTrue(zip.hasArchiveComment)
            assertEquals(3, zip.entries.size)
        }
    }

    @Test
    fun `with a data descriptor the central directory is the authority`() = runTest {
        // Local headers in this fixture carry zero sizes and general-purpose
        // bit 3. A reader that trusts the local header reads zero bytes.
        source("data-descriptor.cbz").use { src ->
            val zip = ZipReader.open(src)

            for (entry in zip.entries.filter { PageOrdering.isPage(it.path) }) {
                assertTrue("central directory size was not used", entry.compressedSize > 0)
                assertEquals(entry.uncompressedSize.toInt(), zip.data(entry).size)
            }
        }
    }

    @Test
    fun `a truncated archive has no findable central directory`() = runTest {
        source("truncated.cbz").use { src ->
            assertThrows(ZipException.NoCentralDirectory::class.java) {
                kotlinx.coroutines.runBlocking { ZipReader.open(src) }
            }
        }
    }

    @Test
    fun `reading one page touches a fraction of the archive`() = runTest {
        // The claim ADR-0008 rests on, measured. This fixture is small, so the
        // interesting number is the *shape*: a bounded tail probe plus one entry,
        // never a full-file read. On a 400 MB archive the same shape means
        // megabytes instead of gigabytes.
        val counter = ReadCounter(source("natural-sort.cbz"))
        counter.use {
            val zip = ZipReader.open(counter)
            zip.data(zip.entries.first())
        }

        // Tail probe, local header probe, entry data. The central directory came
        // out of the tail read, which is the common case for a comic.
        assertTrue("expected a handful of ranged reads, got ${counter.reads}", counter.reads <= 4)
    }

    @Test
    fun `reads are bounds-checked against the source, not against a header`() = runTest {
        val src = DataSource(ByteArray(100))

        assertThrows(SourceOutOfBoundsException::class.java) {
            kotlinx.coroutines.runBlocking { src.readExactly(90, 20) }
        }
    }

    @Test
    fun `a source with no EOCD signature at all is reported as such`() = runTest {
        val src = DataSource(ByteArray(1024) { 0x41 })

        assertThrows(ZipException.NoCentralDirectory::class.java) {
            kotlinx.coroutines.runBlocking { ZipReader.open(src) }
        }
    }

    @Test
    fun `a lying uncompressed size cannot make the reader allocate without bound`() {
        // The size comes from the central directory, which is attacker
        // controlled. This is the guard, asserted directly.
        assertThrows(ZipException.Malformed::class.java) {
            ZipReader.inflate(byteArrayOf(0), -1)
        }
        assertEquals(0, ZipReader.inflate(ByteArray(0), 0).size)
    }
}

class RandomAccessSourceTest {
    @Test
    fun `a file source reports its real length and reads at an offset`() = runTest {
        val file = FixtureCorpus.file("comics/natural-sort.cbz")
        val whole = file.readBytes()

        FileSource(file).use { src ->
            assertEquals(whole.size.toLong(), src.length)
            assertTrue(src.read(100, 16).contentEquals(whole.copyOfRange(100, 116)))
        }
    }

    @Test
    fun `a tail read returns the last bytes and their offset`() = runTest {
        val src = DataSource(ByteArray(100) { it.toByte() })

        val (data, offset) = src.readTail(10)

        assertEquals(90L, offset)
        assertTrue(data.contentEquals(ByteArray(10) { (it + 90).toByte() }))
    }

    @Test
    fun `a tail read larger than the source returns the whole source`() = runTest {
        val src = DataSource(ByteArray(10))

        val (data, offset) = src.readTail(500)

        assertEquals(0L, offset)
        assertEquals(10, data.size)
    }
}
