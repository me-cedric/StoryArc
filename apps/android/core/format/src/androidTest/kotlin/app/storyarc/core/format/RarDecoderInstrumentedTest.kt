package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The one place libarchive is exercised on Android.
 *
 * Instrumented because the decoder is a JNI library: it does not exist on a host
 * JVM, which is why `RarDecoder.isAvailable` is false there and the JVM suite
 * asserts the header reader instead.
 *
 * The fixtures are vendored from libarchive's own test suite because a RAR
 * compressor is proprietary, and — more importantly — because their expected
 * contents are documented in libarchive's assertions rather than produced by our
 * decoder. iOS's `RarDecoderTests` asserts exactly the same values.
 */
@RunWith(AndroidJUnit4::class)
class RarDecoderInstrumentedTest {

    private fun fixture(name: String): File {
        val context = InstrumentationRegistry.getInstrumentation().context
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    /**
     * libarchive's own generator for `test.bin`: each little-endian 32-bit word at
     * index `i` is `max(0, k*k - 3*k + 1)` for `k = i + 1`. Reproduced here so the
     * assertion is independent of the decoder under test.
     */
    private fun expectedBinContent(byteCount: Int): ByteArray {
        val buffer = ByteBuffer.allocate(byteCount).order(ByteOrder.LITTLE_ENDIAN)
        for (index in 0 until byteCount / 4) {
            val k = index + 1
            buffer.putInt(maxOf(0, k * k - 3 * k + 1))
        }
        return buffer.array()
    }

    @Test
    fun theNativeDecoderIsPresentOnADevice() {
        // If this fails the CMake build did not package a .so for this ABI, and
        // every other test here would fail for a misleading reason.
        assertTrue("libstoryarc_rar did not load", RarDecoder.isAvailable)
    }

    @Test
    fun rar5CompressionDecodesToTheExactBytesLibarchivesSuiteExpects() {
        val data = RarDecoder.data(fixture("comics/rar5-compressed.cbr"), "test.bin")
        assertEquals(1200, data.size)
        assertArrayEquals(expectedBinContent(1200), data)
    }

    @Test
    fun rar4CompressionDecodesToTheExactBytesLibarchivesSuiteExpects() {
        val archive = fixture("comics/rar4-compressed.cbr")
        val data = RarDecoder.data(archive, "test.txt")
        assertEquals("test text document\r\n", String(data))
        // The same content again from a nested directory, which is where a real
        // comic's chapter folders would sit.
        assertArrayEquals(data, RarDecoder.data(archive, "testdir/test.txt"))
    }

    @Test
    fun aSolidRar5DecodesEveryEntryWhichIsWhyItIsNotRefused() {
        val archive = fixture("comics/rar5-solid.cbr")
        assertEquals(7, RarDecoder.entryNames(archive).size)
        // Reading the last entry means decompressing all the ones before it. If
        // solid support were missing this is where it would fail.
        assertEquals(4096, RarDecoder.data(archive, "test6.bin").size)
    }

    @Test
    fun aSolidRar4FailsInLibarchiveWhichIsWhyWeRefuseItOurselves() {
        // The exact behaviour RarComicArchive exists to pre-empt: the first entry
        // is listed, and only then does libarchive give up.
        assertThrows(RarException.Malformed::class.java) {
            RarDecoder.entryNames(fixture("comics/rar4-solid.cbr"))
        }
    }

    @Test
    fun ourHeaderReaderAndLibarchiveSeeTheSameEntries() = runBlocking {
        for (name in listOf(
            "rar4-store.cbr", "rar5-store.cbr", "rar5-compressed.cbr", "rar5-solid.cbr",
        )) {
            val file = fixture("comics/$name")
            val ours = RarReader.open(FileSource(file))
            // RarReader lists only files, so directory entries are filtered out of
            // libarchive's list before comparing. If the two ever disagree about
            // names or sizes, the library would show a page count the reader
            // cannot deliver.
            val theirs = RarDecoder.entryNames(file).filterNot { it.path.endsWith("/") }
            assertEquals(name, theirs.map { it.path }, ours.entries.map { it.path })
            assertEquals(name, theirs.map { it.size }, ours.entries.map { it.size })
        }
    }

    @Test
    fun severalEntriesComeBackFromOnePassOverTheArchive() {
        val wanted = listOf("test.bin", "test3.bin", "test6.bin")
        val found = RarDecoder.data(fixture("comics/rar5-solid.cbr"), wanted)
        assertEquals(wanted.toSet(), found.keys)
        assertEquals(1200, found["test.bin"]?.size)
        assertEquals(4096, found["test6.bin"]?.size)
    }

    @Test
    fun askingForNothingDoesNoWork() {
        assertTrue(RarDecoder.data(fixture("comics/rar5-compressed.cbr"), emptyList()).isEmpty())
    }

    @Test
    fun aMissingEntryIsNamedRatherThanReturningEmptyData() {
        assertThrows(RarException.Malformed::class.java) {
            RarDecoder.data(fixture("comics/rar5-compressed.cbr"), "nope.png")
        }
    }

    @Test
    fun aFileThatIsNotARarIsRefusedAtOpen() {
        assertThrows(RarException.Malformed::class.java) {
            RarDecoder.entryNames(fixture("comics/natural-sort.cbz"))
        }
    }

    @Test
    fun aStoredCbrStillReadsThroughTheHeaderReaderRatherThanTheDecoder() = runBlocking {
        // The split this whole design rests on: a stored entry never reaches
        // libarchive, so the cheap path stays cheap.
        val archive = ComicArchiveOpener.open(fixture("comics/rar5-store.cbr"))
        assertEquals(3, archive.pages.size)
        val page = archive.data(archive.pages.first())
        assertArrayEquals(
            byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
            page.copyOfRange(0, 8),
        )
    }
}
