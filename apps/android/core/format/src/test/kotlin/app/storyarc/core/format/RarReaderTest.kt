package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Asserted against the shared corpus in `packages/test-fixtures`. iOS's
 * `RarReaderTests` asserts the same things about the same files.
 *
 * These fixtures are store-mode, which is exactly the point: the reader parses
 * headers and reads stored bytes, and a compressed entry is the one case it hands
 * on to a decoder. See [RarReader] for why that split exists.
 */
class RarReaderTest {
    private suspend fun reader(name: String) =
        RarReader.open(FileSource(FixtureCorpus.file("comics/$name")))

    @Test
    fun `rar4 and rar5 are told apart, not lumped together as cbr`() = runTest {
        assertEquals(RarGeneration.RAR4, reader("rar4-store.cbr").generation)
        assertEquals(RarGeneration.RAR5, reader("rar5-store.cbr").generation)
        assertEquals(RarGeneration.RAR4, reader("rar4-solid.cbr").generation)
    }

    @Test
    fun `entries carry their names and unpacked sizes`() = runTest {
        for (name in listOf("rar4-store.cbr", "rar5-store.cbr")) {
            val reader = reader(name)
            val fixture = FixtureCorpus.comic(name)
            assertEquals(name, fixture.expectedPageOrder, reader.entries.map { it.path })
            assertTrue(name, reader.entries.all { it.size > 0 })
        }
    }

    @Test
    fun `a stored entry's bytes come back without a decoder`() = runTest {
        for (name in listOf("rar4-store.cbr", "rar5-store.cbr")) {
            val reader = reader(name)
            val entry = reader.entries.first()
            assertTrue(name, entry.isStored)
            val data = reader.data(entry)
            assertEquals(name, entry.size.toInt(), data.size)
            // A PNG signature proves the offset arithmetic landed on the data
            // rather than on a header.
            assertArrayEquals(
                byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
                data.copyOfRange(0, 8),
            )
        }
    }

    @Test
    fun `a non-solid archive reports itself streamable`() = runTest {
        for (name in listOf("rar4-store.cbr", "rar5-store.cbr")) {
            val reader = reader(name)
            assertFalse(name, reader.isSolid)
            assertFalse(name, reader.isEncrypted)
        }
    }

    // Solid.

    @Test
    fun `a solid archive is detected from its flags, before any entry is read`() = runTest {
        val reader = reader("rar4-solid.cbr")
        val fixture = FixtureCorpus.comic("rar4-solid.cbr")
        assertTrue(reader.isSolid)
        assertEquals(true, fixture.isSolid)
        assertEquals(false, fixture.isStreamable)
        // The finding this pins: libarchive lists the first entry and *then*
        // fails, because the first entry of a solid archive is not itself solid.
        // Detection has to look at every entry, not just the first.
        assertFalse(reader.entries.first().isSolid)
        assertTrue(reader.entries.drop(1).any { it.isSolid })
    }

    @Test
    fun `a solid archive is refused by name rather than opened`() = runTest {
        val failure = runCatching {
            ComicArchiveOpener.open(FixtureCorpus.file("comics/rar4-solid.cbr"))
        }.exceptionOrNull()
        assertTrue("expected SolidArchive, got $failure", failure is ComicArchiveException.SolidArchive)
    }

    @Test
    fun `a compressed entry names the decoder it needs rather than failing vaguely`() = runTest {
        // Same fixture, with the method byte flipped from store to LZ. The
        // headers stay valid, so this isolates the one case a decoder is for.
        val bytes = FixtureCorpus.file("comics/rar4-store.cbr").readBytes()
        // signature, then the 13-byte main header, then METHOD at offset 25
        // inside the file header.
        val methodOffset = RarReader.RAR4_SIGNATURE.size + 13 + 25
        assertEquals("expected the store method byte here", 0x30, bytes[methodOffset].toInt())
        bytes[methodOffset] = 0x33
        val reader = RarReader.open(DataSource(bytes))
        val entry = reader.entries.first()
        assertFalse(entry.isStored)
        val failure = runCatching { reader.data(entry) }.exceptionOrNull()
        assertTrue("expected NeedsDecoder, got $failure", failure is RarException.NeedsDecoder)
    }

    // Untrusted input.

    @Test
    fun `a signature with nothing behind it yields no entries, not a crash`() = runTest {
        val reader = RarReader.open(DataSource(RarReader.RAR5_SIGNATURE))
        assertTrue(reader.entries.isEmpty())
    }

    @Test
    fun `bytes that are not a rar are rejected as such`() = runTest {
        val failure = runCatching {
            RarReader.open(DataSource(ByteArray(512) { 0x41 }))
        }.exceptionOrNull()
        assertTrue("expected NotRar, got $failure", failure is RarException.NotRar)
    }

    @Test
    fun `a header claiming a size past the end of the file stops the walk`() = runTest {
        val bytes = RarReader.RAR5_SIGNATURE +
            byteArrayOf(0, 0, 0, 0) + // header CRC
            byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0x7F) // absurd header size
        val reader = RarReader.open(DataSource(bytes))
        assertTrue(reader.entries.isEmpty())
    }

    @Test
    fun `a run of continuation bytes cannot spin the vint reader`() {
        val cursor = RarReader.Cursor(0)
        assertEquals(null, RarReader.vint(ByteArray(64) { 0x80.toByte() }, cursor))
        assertTrue(cursor.value <= 10)
    }
}
