package app.storyarc.core.format

import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * A source that counts how many times it was asked for bytes, and never answers with more
 * than it was told it may hold at once -- the way a real transport actually behaves, and the
 * property a one-shot `read(0, entry.length.toInt())` call does not have to respect.
 */
private class CountingSource(private val bytes: ByteArray, private val maxPerRead: Int) :
    RandomAccessSource {
    val reads = mutableListOf<Pair<Long, Int>>()

    override val length: Long = bytes.size.toLong()

    override suspend fun read(offset: Long, count: Int): ByteArray {
        reads.add(offset to count)
        val capped = minOf(count, maxPerRead)
        val start = offset.toInt()
        val end = minOf(start + capped, bytes.size)
        if (start > bytes.size) return ByteArray(0)
        return bytes.copyOfRange(start, end)
    }
}

/**
 * `ChunkedCopy` is what stands between a large publication and a transport that refuses a
 * single oversized read -- SMB's own reply is capped by its wire format, and `Int` overflow
 * on a length past 2 GiB is the other half of the same defect. This is the one place both
 * are respected rather than assumed away.
 */
class ChunkedCopyTest {
    @get:Rule
    val scratch = TemporaryFolder()

    @Test
    fun `the whole source lands on disk byte for byte`() = runTest {
        val bytes = ByteArray(5000) { (it % 256).toByte() }
        val source = CountingSource(bytes, maxPerRead = 700)
        val destination = File(scratch.root, "copy.cbz")

        ChunkedCopy.copy(source, destination, chunkSize = 1024)

        assertArrayEquals(bytes, destination.readBytes())
    }

    @Test
    fun `a source larger than the chunk size is read more than once`() = runTest {
        // The property a one-shot `read(0, source.length.toInt())` cannot have: more than one
        // call, none of them asking for the whole length in a single message.
        val bytes = ByteArray(10_000) { 0x42 }
        val source = CountingSource(bytes, maxPerRead = 10_000)
        val destination = File(scratch.root, "copy.cbz")

        ChunkedCopy.copy(source, destination, chunkSize = 2000)

        assertEquals(5, source.reads.size)
        assertTrue(source.reads.all { (_, count) -> count <= 2000 })
    }

    @Test
    fun `no partial file is left beside a finished copy`() = runTest {
        val source = CountingSource(ByteArray(100) { 1 }, maxPerRead = 100)
        val destination = File(scratch.root, "copy.cbz")

        ChunkedCopy.copy(source, destination)

        assertFalse(File(scratch.root, "copy.cbz.partial").exists())
    }

    @Test
    fun `a copy that throws mid-way leaves neither a partial nor a destination file`() {
        class Boom : Exception()
        val failing = object : RandomAccessSource {
            override val length = 10_000L
            override suspend fun read(offset: Long, count: Int): ByteArray {
                if (offset > 0) throw Boom()
                return ByteArray(count)
            }
        }
        val destination = File(scratch.root, "copy.cbz")

        // `assertThrows` over the file's own `runBlocking` idiom, matching
        // `ComicArchiveTest`: it names the expected type, so a copy that throws the wrong
        // kind of error fails as loudly as one that does not throw at all.
        assertThrows(Boom::class.java) {
            kotlinx.coroutines.runBlocking {
                ChunkedCopy.copy(failing, destination, chunkSize = 1000)
            }
        }

        assertFalse(destination.exists())
        assertFalse(File(scratch.root, "copy.cbz.partial").exists())
    }

    @Test
    fun `a source that ends before its stated length fails rather than leaving a short file`() {
        val short = object : RandomAccessSource {
            override val length = 10_000L
            override suspend fun read(offset: Long, count: Int): ByteArray =
                if (offset < 4_000) ByteArray(minOf(count, (4_000 - offset).toInt())) else ByteArray(0)
        }
        val destination = File(scratch.root, "copy.cbz")

        assertThrows(SourceUnreadableException::class.java) {
            kotlinx.coroutines.runBlocking {
                ChunkedCopy.copy(short, destination, chunkSize = 1000)
            }
        }

        assertFalse(destination.exists())
        assertFalse(File(scratch.root, "copy.cbz.partial").exists())
    }
}
