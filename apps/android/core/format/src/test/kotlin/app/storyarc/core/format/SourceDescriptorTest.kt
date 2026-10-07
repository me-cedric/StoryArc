package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The read a proxy descriptor makes for `PdfRenderer` (14.15).
 *
 * The descriptor itself needs a device, and `PdfStreamingInstrumentedTest` counts what a
 * render reads through it. This pins the copy each kernel read makes: only the range asked
 * for, clamped to the source and to the buffer.
 */
class SourceDescriptorTest {

    private class Recording(private val data: ByteArray) : RandomAccessSource {
        val reads = mutableListOf<Pair<Long, Int>>()
        override val length: Long = data.size.toLong()

        override suspend fun read(offset: Long, count: Int): ByteArray {
            reads += offset to count
            return data.copyOfRange(offset.toInt(), minOf(offset.toInt() + count, data.size))
        }
    }

    private val bytes = ByteArray(100) { it.toByte() }

    @Test
    fun `a read asks the source for that range and nothing else`() = runTest {
        val source = Recording(bytes)
        val buffer = ByteArray(10)

        assertEquals(10, readInto(source, 40, 10, buffer))
        assertArrayEquals(bytes.copyOfRange(40, 50), buffer)
        assertEquals(listOf(40L to 10), source.reads)
    }

    @Test
    fun `a read past the end is clamped, and at the end it is zero`() = runTest {
        val source = Recording(bytes)
        val buffer = ByteArray(10)

        assertEquals(4, readInto(source, 96, 10, buffer))
        assertEquals(0, readInto(source, 100, 10, buffer))
        assertEquals(listOf(96L to 4), source.reads)
    }

    @Test
    fun `a read never asks for more than the buffer holds`() = runTest {
        val source = Recording(bytes)

        assertEquals(3, readInto(source, 0, 50, ByteArray(3)))
        assertEquals(listOf(0L to 3), source.reads)
    }
}
