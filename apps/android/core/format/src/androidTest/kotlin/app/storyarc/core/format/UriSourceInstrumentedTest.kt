package app.storyarc.core.format

import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Bytes out of a content `Uri`.
 *
 * The whole of Android's Storage Access Framework support rests on this type: a
 * folder the user picks has no path, so every reader reaches it through a
 * [UriSource] or not at all. Instrumented because a `ContentResolver` and a real
 * `ParcelFileDescriptor` are the two things a host JVM does not have.
 */
@RunWith(AndroidJUnit4::class)
class UriSourceInstrumentedTest {

    private val context = InstrumentationRegistry.getInstrumentation().context
    private val resolver get() = context.contentResolver

    private fun fixture(name: String): File {
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    private fun uriFor(file: File) =
        FileProvider.getUriForFile(context, "app.storyarc.core.format.test", file)

    @Test
    fun reads_the_same_bytes_as_the_file() = runBlocking {
        val file = fixture("comics/natural-sort.cbz")
        val expected = file.readBytes()

        UriSource(resolver, uriFor(file)).use { source ->
            assertEquals(expected.size.toLong(), source.length)
            assertArrayEquals(expected.copyOfRange(0, 64), source.read(0, 64))
            // An offset in the middle: a stream would have to be re-read from the
            // start to answer this, which is the whole reason for the type.
            val offset = expected.size / 2L
            assertArrayEquals(
                expected.copyOfRange(offset.toInt(), offset.toInt() + 32),
                source.read(offset, 32),
            )
        }
    }

    @Test
    fun a_read_past_the_end_is_short_rather_than_an_error() = runBlocking {
        val file = fixture("comics/single-page.cbz")
        UriSource(resolver, uriFor(file)).use { source ->
            val tail = source.read(source.length - 4, 64)
            assertEquals(4, tail.size)
            assertEquals(0, source.read(source.length, 16).size)
        }
    }

    @Test
    fun the_descriptor_path_opens_the_same_file() = runBlocking {
        val file = fixture("comics/rar5-store.cbr")
        UriSource(resolver, uriFor(file)).use { source ->
            val viaProc = File(source.descriptorPath)
            assertTrue("$viaProc should be readable", viaProc.canRead())
            // This is what libarchive is handed for a CBR from a picked folder.
            assertArrayEquals(file.readBytes(), viaProc.readBytes())
        }
    }

    @Test
    fun a_whole_archive_opens_through_the_resolver() = runBlocking {
        val file = fixture("comics/natural-sort.cbz")
        ComicArchiveOpener.open(resolver, uriFor(file)).use { archive ->
            assertEquals(12, archive.pages.size)
            assertTrue(archive.data(archive.pages.first()).isNotEmpty())
        }
    }
}
