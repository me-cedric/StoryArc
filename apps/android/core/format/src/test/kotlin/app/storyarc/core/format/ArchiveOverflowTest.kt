package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Archives whose header fields are chosen to overflow a 64-bit integer.
 *
 * The mirror of iOS's `ArchiveOverflowTests`, in the same order. **Kotlin is not the
 * platform this class of bug bites.** `Long` arithmetic wraps here rather than trapping,
 * and the wrapped negative is then refused — by `readExactly`, by an array copy, or by a
 * truncating conversion that leaves the index empty. So the safety property asserted here
 * is the weaker one Android actually has: the reader ends in an exception `LibraryScanner`
 * catches, or it surfaces nothing readable. Never a process abort, which is where iOS was.
 *
 * Asserted anyway, because the two readers are deliberate mirrors and a case only one
 * suite knows about is how the pair drifts.
 */
class ArchiveOverflowTest {
    @Test
    fun `a zip64 locator pointing near Long MAX_VALUE is refused, not added to`() = runTest {
        val bytes = Crafted()
        bytes.raw(ByteArray(64))
        bytes.zip64Locator(0x7FFFFFFFFFFFFFC8L)
        bytes.endOfCentralDirectory(0, 0, 0)

        assertNothingReadable(bytes.data())
    }

    @Test
    fun `a zip64 record whose directory size and offset sum past Long MAX_VALUE is refused`() =
        runTest {
            val bytes = Crafted()
            bytes.zip64EndOfCentralDirectory(0x4000000000000000L, 0x4000000000000000L)
            bytes.zip64Locator(0L)
            bytes.endOfCentralDirectory(0, 0, 0)

            assertNothingReadable(bytes.data())
        }

    @Test
    fun `a zip64 extra field cannot give an entry a usable negative local header offset`() =
        runTest {
            val bytes = Crafted()
            bytes.localHeader("page1.png")
            val directoryOffset = bytes.size()
            bytes.centralDirectoryEntry("page1.png", Long.MIN_VALUE)
            val directorySize = bytes.size() - directoryOffset
            bytes.endOfCentralDirectory(1, directorySize, directoryOffset)

            val failure = runCatching {
                val zip = ZipReader.open(DataSource(bytes.data()))
                zip.data(zip.entries.first())
            }.exceptionOrNull()
            assertNotNull("an entry outside the file was read", failure)
        }

    @Test
    fun `a gnu base-256 tar size near Long MAX_VALUE does not overflow the block padding`() =
        runTest {
            val header = ByteArray(512)
            "page1.png".toByteArray().copyInto(header, 0)
            "ustar".toByteArray().copyInto(header, TarReader.MAGIC_OFFSET)
            header[156] = 0x30 // regular file
            // High bit set marks base-256; the remaining bytes are the integer, big-endian.
            byteArrayOf(
                0x80.toByte(), 0x00, 0x00, 0x00,
                0x7F, 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(),
                0xFF.toByte(), 0xFF.toByte(), 0xFE.toByte(), 0xFF.toByte(),
            ).copyInto(header, 124)
            writeChecksum(header)

            // Either outcome is safe; what must not happen is an entry claiming
            // Long.MAX_VALUE bytes coming back as readable.
            val reader = runCatching { TarReader.open(DataSource(header)) }.getOrNull()
            assertTrue(
                "an entry claiming Long.MAX_VALUE bytes was surfaced",
                reader == null || reader.entries.isEmpty(),
            )
        }

    /**
     * The archive is refused, or it yields no entry. Either is safe; between them they are
     * everything Android does with a header field that wrapped.
     */
    private suspend fun assertNothingReadable(bytes: ByteArray) {
        val reader = runCatching { ZipReader.open(DataSource(bytes)) }.getOrNull()
        assertTrue(
            "a crafted archive surfaced ${reader?.entries?.size} readable entries",
            reader == null || reader.entries.isEmpty(),
        )
    }

    /** The checksum a real TAR writer would have written for this header. */
    private fun writeChecksum(header: ByteArray) {
        for (index in 148 until 156) header[index] = 0x20
        val sum = header.sumOf { it.toInt() and 0xFF }
        val field = String.format("%06o", sum).toByteArray() + byteArrayOf(0x00, 0x20)
        field.copyInto(header, 148)
    }
}

/** Bytes assembled by hand, because no archive writer produces these. */
private class Crafted {
    private val bytes = mutableListOf<Byte>()

    fun data(): ByteArray = bytes.toByteArray()

    fun size(): Long = bytes.size.toLong()

    fun raw(value: ByteArray) {
        bytes += value.toList()
    }

    fun uint16(value: Int) {
        bytes += (value and 0xFF).toByte()
        bytes += ((value shr 8) and 0xFF).toByte()
    }

    fun uint32(value: Long) {
        for (shift in 0 until 4) bytes += ((value shr (shift * 8)) and 0xFF).toByte()
    }

    fun uint64(value: Long) {
        for (shift in 0 until 8) bytes += ((value shr (shift * 8)) and 0xFF).toByte()
    }

    fun localHeader(name: String) {
        uint32(0x04034B50)
        uint16(20) // version needed
        uint16(0) // flags
        uint16(0) // method: stored
        uint32(0) // time and date
        uint32(0) // crc
        uint32(0) // compressed size
        uint32(0) // uncompressed size
        uint16(name.toByteArray().size)
        uint16(0) // extra length
        raw(name.toByteArray())
    }

    /**
     * A central directory entry whose local header offset is the zip64 sentinel, with the
     * real value carried in the extra field where nothing range-checked it.
     */
    fun centralDirectoryEntry(name: String, zip64LocalOffset: Long) {
        uint32(0x02014B50)
        uint16(20) // version made by
        uint16(20) // version needed
        uint16(0) // flags
        uint16(0) // method: stored
        uint32(0) // time and date
        uint32(0) // crc
        uint32(0) // compressed size
        uint32(0) // uncompressed size
        uint16(name.toByteArray().size)
        uint16(12) // extra length: one zip64 block
        uint16(0) // comment length
        uint16(0) // disk start
        uint16(0) // internal attributes
        uint32(0) // external attributes
        uint32(0xFFFFFFFFL) // local offset: "read the zip64 extra field"
        raw(name.toByteArray())
        uint16(0x0001) // zip64 extended information
        uint16(8)
        uint64(zip64LocalOffset)
    }

    fun zip64EndOfCentralDirectory(size: Long, offset: Long) {
        uint32(0x06064B50)
        uint64(44) // record size
        uint16(45) // version made by
        uint16(45) // version needed
        uint32(0) // this disk
        uint32(0) // disk with the central directory
        uint64(1) // entries on this disk
        uint64(1) // entries in total
        uint64(size)
        uint64(offset)
    }

    fun zip64Locator(recordOffset: Long) {
        uint32(0x07064B50)
        uint32(0) // disk holding the zip64 EOCD
        uint64(recordOffset)
        uint32(1) // total disks
    }

    fun endOfCentralDirectory(entryCount: Int, size: Long, offset: Long) {
        uint32(0x06054B50)
        uint16(0) // this disk
        uint16(0) // disk with the central directory
        uint16(entryCount) // entries on this disk
        uint16(entryCount) // entries in total
        uint32(size and 0xFFFFFFFFL)
        uint32(offset and 0xFFFFFFFFL)
        uint16(0) // comment length
    }
}
