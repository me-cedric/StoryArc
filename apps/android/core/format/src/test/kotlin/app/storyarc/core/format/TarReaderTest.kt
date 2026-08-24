package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Asserted against the shared corpus in `packages/test-fixtures`. iOS's
 * `TarReaderTests` asserts the same things about the same files.
 */
class TarReaderTest {
    private suspend fun reader(name: String) =
        TarReader.open(FileSource(FixtureCorpus.file("comics/$name")))

    @Test
    fun `a tar is identified by its magic at offset 257, not by its extension`() = runTest {
        val source = FileSource(FixtureCorpus.file("comics/tar-store.cbt"))
        val probe = source.read(0, FormatSniffer.PROBE_LENGTH)
        assertEquals(FormatSniffer.Container.TAR, FormatSniffer.container(probe))
    }

    @Test
    fun `the probe reaches far enough to see the tar magic`() {
        // If someone shrinks PROBE_LENGTH back to 8 for the other containers,
        // CBT detection silently stops working. This is the guard.
        assertTrue(FormatSniffer.PROBE_LENGTH >= TarReader.MAGIC_OFFSET + 5)
    }

    @Test
    fun `entries keep archive order and report their real sizes`() = runTest {
        val reader = reader("tar-store.cbt")
        assertEquals(listOf("page1.png", "page2.png", "page3.png"), reader.entries.map { it.path })
        assertTrue(reader.entries.all { it.size > 0 })
    }

    @Test
    fun `chapter directories are read as paths, and directory blocks are not pages`() = runTest {
        val reader = reader("tar-nested-chapters.cbt")
        assertEquals(
            listOf("ch1/p1.png", "ch1/p2.png", "ch2/p1.png"),
            reader.entries.map { it.path },
        )
    }

    @Test
    fun `entry bytes come back verbatim — tar stores no compression`() = runTest {
        val reader = reader("tar-store.cbt")
        val entry = reader.entries.first()
        val data = reader.data(entry)
        assertEquals(entry.size.toInt(), data.size)
        // Every fixture page is a PNG, so the signature proves the offset
        // arithmetic landed on the data block rather than on a header.
        assertArrayEquals(
            byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
            data.copyOfRange(0, 8),
        )
    }

    @Test
    fun `a cbt opens through the same opener as every other container`() = runTest {
        val archive = ComicArchiveOpener.open(FixtureCorpus.file("comics/tar-store.cbt"))
        val fixture = FixtureCorpus.comic("tar-store.cbt")
        assertEquals(fixture.expectedPageOrder, archive.pages.map { it.path })
        assertEquals(0, archive.skippedPageCount)
    }

    // Untrusted input.

    @Test
    fun `a block whose checksum does not match is not accepted as a header`() = runTest {
        val bytes = ByteArray(1024)
        "page1.png".toByteArray().copyInto(bytes, 0)
        "ustar".toByteArray().copyInto(bytes, TarReader.MAGIC_OFFSET)
        // Deliberately no checksum field. A parser that trusts the magic alone
        // would read a 512-byte block of zeros as an entry.
        val failure = runCatching { TarReader.open(DataSource(bytes)) }.exceptionOrNull()
        assertTrue("expected NotTar, got $failure", failure is TarException.NotTar)
    }

    @Test
    fun `a header claiming more bytes than the file holds yields no entry`() = runTest {
        val header = ByteArray(512)
        "page1.png".toByteArray().copyInto(header, 0)
        "ustar".toByteArray().copyInto(header, TarReader.MAGIC_OFFSET)
        header[156] = 0x30 // regular file
        // 8 GB of data behind a 512-byte file.
        "77777777777".toByteArray().copyInto(header, 124)
        writeChecksum(header)

        val reader = TarReader.open(DataSource(header))
        // The header parses, so this is not "not a TAR" — but the entry cannot be
        // surfaced, because its bytes are not there.
        assertTrue(reader.entries.isEmpty())
    }

    @Test
    fun `an empty source is not mistaken for an empty archive`() = runTest {
        val failure = runCatching { TarReader.open(DataSource(ByteArray(0))) }.exceptionOrNull()
        assertTrue("expected NotTar, got $failure", failure is TarException.NotTar)
    }

    /** The checksum a real TAR writer would have written for this header. */
    private fun writeChecksum(header: ByteArray) {
        for (index in 148 until 156) header[index] = 0x20
        val sum = header.sumOf { it.toInt() and 0xFF }
        val field = String.format("%06o", sum).toByteArray() + byteArrayOf(0x00, 0x20)
        field.copyInto(header, 148)
    }
}
