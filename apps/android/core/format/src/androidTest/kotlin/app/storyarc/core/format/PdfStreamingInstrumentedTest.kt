package app.storyarc.core.format

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfDocument
import android.os.storage.StorageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.util.Random

/**
 * A PDF on a share streams on Android: `PdfRenderer` reads it through a proxy descriptor,
 * and only the ranges it asks for cross the source (close-the-audited-gaps 14.15, O4).
 *
 * Instrumented because `PdfRenderer` and `StorageManager` exist only on a device. The PDF is
 * written here: forty pages, each carrying an incompressible image, so that page one is a
 * small part of the file.
 */
@RunWith(AndroidJUnit4::class)
class PdfStreamingInstrumentedTest {

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

    private fun largePdf(): ByteArray {
        val document = PdfDocument()
        val random = Random(7)
        repeat(PAGES) { index ->
            val page = document.startPage(PdfDocument.PageInfo.Builder(400, 400, index + 1).create())
            val pixels = IntArray(300 * 300) { random.nextInt() or Color.BLACK }
            val image = Bitmap.createBitmap(pixels, 300, 300, Bitmap.Config.ARGB_8888)
            page.canvas.drawBitmap(image, 50f, 50f, null)
            document.finishPage(page)
        }
        return ByteArrayOutputStream().also { document.writeTo(it); document.close() }.toByteArray()
    }

    @Test
    fun aRemotePdfRendersItsFirstPageWithoutReadingTheWholeFile() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val bytes = largePdf()
        val source = CountingSource(bytes)
        PublicationAccess.streamPdfsThrough(context.getSystemService(StorageManager::class.java))
        PublicationAccess.register(SCHEME) { source }

        PublicationAccess.openPdf(context.contentResolver, "$SCHEME://nas/scan.pdf").use { reader ->
            assertEquals(PAGES, reader.pageCount)
            val page = reader.render(0, maxPixelSize = 400)
            assertTrue(page.width > 0)
        }

        assertTrue(
            "PdfRenderer read ${source.bytesRead} of ${bytes.size} bytes to draw page one",
            source.bytesRead < bytes.size / 4,
        )
    }

    private companion object {
        const val SCHEME = "storyarc-pdf-test"
        const val PAGES = 40
    }
}
