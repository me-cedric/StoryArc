package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.zip.CRC32

/**
 * A non-solid CBR streams: a compressed page decodes from its own ranged bytes.
 *
 * `publication-formats` marks a non-solid CBR as *Streams* and a solid RAR5 as *Download
 * only*. Each test counts what the ranged source reads, so a read that fell back to the whole
 * file fails by name. The decode itself needs the JNI library, which a host JVM does not
 * have: `RarDecoderInstrumentedTest` decodes these same slices on a device. iOS's
 * `RarStreamingTests` asserts the same slices and decodes them on the host.
 */
class RarStreamingTest {

    @Test
    fun `a compressed RAR5 entry is read as its own bytes, and nothing else`() = runTest {
        val bytes = storedPagesThenCompressedEntry()
        val source = RangeCountingSource(bytes)
        val reader = RarReader.open(source)
        val compressed = reader.entries.single { it.path == "test.bin" }
        val stored = reader.entries.filter { it.isStored }
        assertEquals(3, stored.size)

        source.reset()
        val slice = reader.isolated(compressed)

        val entryEnd = (compressed.dataOffset + compressed.packedSize).toInt()
        val expected = bytes.copyOfRange(0, reader.mainHeaderEnd.toInt()) +
            bytes.copyOfRange(compressed.headerOffset.toInt(), entryEnd)
        assertArrayEquals(expected, slice)
        assertEquals(slice.size, source.bytesRead)
        assertTrue(source.bytesRead < bytes.size)
        for (entry in stored) {
            assertFalse(
                "reading test.bin read the bytes of ${entry.path}",
                source.touched(entry.dataOffset, entry.dataOffset + entry.packedSize),
            )
        }
    }

    @Test
    fun `a RAR4 entry is read without the entry before it`() = runTest {
        val source = RangeCountingSource(FixtureCorpus.file("comics/rar4-compressed.cbr").readBytes())
        val reader = RarReader.open(source)
        val first = reader.entries.first()
        val nested = reader.entries.single { it.path == "testdir\\test.txt" }

        source.reset()
        val slice = reader.isolated(nested)

        assertEquals(
            (reader.mainHeaderEnd + nested.dataOffset + nested.packedSize - nested.headerOffset).toInt(),
            source.bytesRead,
        )
        assertEquals(slice.size, source.bytesRead)
        assertFalse(source.touched(first.dataOffset, first.dataOffset + first.packedSize))
    }

    @Test
    fun `a non-solid compressed CBR with no file is not download-only`() = runTest {
        val bytes = renamed(storedPagesThenCompressedEntry())
        val archive = RarComicArchive.open(DataSource(bytes), file = null, decoderPresent = true)
        assertTrue(archive.isStreamable)
        assertFalse(archive.isDownloadOnly)
        // With no native library at all, nothing compressed can be read anywhere.
        assertTrue(RarComicArchive.open(DataSource(bytes), file = null, decoderPresent = false).isDownloadOnly)
    }

    @Test
    fun `a solid RAR5 stays download-only, and its pages are not decoded by range`() = runTest {
        val solid = FixtureCorpus.file("comics/rar5-solid.cbr").readBytes()
        val bytes = renamed(solid, mapOf("test3.bin" to "test3.png"))
        val source = RangeCountingSource(bytes)
        val archive = RarComicArchive.open(source, file = null, decoderPresent = true)
        assertFalse(archive.isStreamable)
        assertTrue(archive.isDownloadOnly)

        source.reset()
        assertThrows(ComicArchiveException.UnsupportedContainer::class.java) {
            kotlinx.coroutines.runBlocking { archive.data(archive.pages.single()) }
        }
        assertEquals(0, source.bytesRead)
    }

    @Test
    fun `an entry whose packed bytes run past the source is refused before any read`() = runTest {
        val bytes = FixtureCorpus.file("comics/rar5-compressed.cbr").readBytes()
        val source = RangeCountingSource(bytes)
        val reader = RarReader.open(source)
        val liar = reader.entries.single().copy(packedSize = bytes.size.toLong())

        source.reset()
        assertThrows(RarException.Malformed::class.java) {
            kotlinx.coroutines.runBlocking { reader.isolated(liar) }
        }
        assertEquals(0, source.bytesRead)
    }

    /**
     * `rar5-store.cbr`'s three stored pages, then `rar5-compressed.cbr`'s compressed entry,
     * then the end block. Every block is copied whole from a fixture.
     */
    private suspend fun storedPagesThenCompressedEntry(): ByteArray {
        val store = FixtureCorpus.file("comics/rar5-store.cbr").readBytes()
        val compressed = FixtureCorpus.file("comics/rar5-compressed.cbr").readBytes()
        val last = RarReader.open(DataSource(store)).entries.last()
        val entry = RarReader.open(DataSource(compressed)).entries.single()
        val pagesEnd = (last.dataOffset + last.packedSize).toInt()
        return store.copyOfRange(0, pagesEnd) +
            compressed.copyOfRange(entry.headerOffset.toInt(), (entry.dataOffset + entry.packedSize).toInt()) +
            store.copyOfRange(pagesEnd, store.size)
    }

    /**
     * [bytes] with each entry named by a key renamed to its value, of the same length, and
     * the header CRC that covers the name rewritten. RAR5 keeps a CRC32 of the header from
     * its size field on.
     */
    private suspend fun renamed(
        bytes: ByteArray,
        names: Map<String, String> = mapOf("test.bin" to "test.png"),
    ): ByteArray {
        val out = bytes.copyOf()
        for (entry in RarReader.open(DataSource(bytes)).entries) {
            val name = names[entry.path] ?: continue
            val old = entry.path.toByteArray()
            val new = name.toByteArray()
            require(old.size == new.size) { "a rename must keep the header length" }
            val from = entry.headerOffset.toInt()
            val to = entry.dataOffset.toInt()
            val at = (from..to - old.size).first { start ->
                old.indices.all { out[start + it] == old[it] }
            }
            new.copyInto(out, at)
            val crc = CRC32().apply { update(out, from + 4, to - from - 4) }.value
            for (index in 0 until 4) out[from + index] = (crc shr (8 * index)).toByte()
        }
        return out
    }
}

/** Counts every byte a read asks for, and where. */
private class RangeCountingSource(private val data: ByteArray) : RandomAccessSource {
    private val ranges = mutableListOf<LongRange>()

    override val length: Long = data.size.toLong()

    val bytesRead: Int get() = synchronized(ranges) { ranges.sumOf { (it.last - it.first + 1).toInt() } }

    fun reset() = synchronized(ranges) { ranges.clear() }

    fun touched(from: Long, until: Long): Boolean = synchronized(ranges) {
        ranges.any { it.first < until && it.last >= from }
    }

    override suspend fun read(offset: Long, count: Int): ByteArray {
        if (offset < 0 || offset > data.size) throw SourceOutOfBoundsException(offset, count, length)
        val end = minOf(offset.toInt() + count, data.size)
        if (end > offset) synchronized(ranges) { ranges += offset until end.toLong() }
        return data.copyOfRange(offset.toInt(), end)
    }
}
