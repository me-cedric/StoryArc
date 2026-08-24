package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Asserted against the shared corpus in `packages/test-fixtures`.
 *
 * iOS's `PdfDocumentReaderTests` asserts everything here **plus** text, search
 * and the outline. That asymmetry is what `ebook-reader` specifies rather than a
 * gap in this file: `PdfRenderer` has no text API at all, so Android renders PDF
 * pages as images and hides text-dependent controls.
 *
 * Instrumented rather than a JVM unit test because `PdfRenderer` and `Bitmap` are
 * framework classes that are stubs off-device — the same reason
 * `PageDecoderInstrumentedTest` is instrumented.
 */
@RunWith(AndroidJUnit4::class)
class PdfDocumentReaderInstrumentedTest {

    private fun fixture(name: String): File {
        // The corpus is packaged as instrumentation assets by the build script and
        // copied out, because PdfRenderer needs a real seekable file descriptor.
        val context = InstrumentationRegistry.getInstrumentation().context
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    private fun <T> reader(name: String, block: (PdfDocumentReader) -> T): T =
        PdfDocumentReader(fixture("comics/$name")).use(block)

    @Test
    fun pageCountMatchesTheManifest() {
        reader("text-pages.pdf") { assertEquals(3, it.pageCount) }
        reader("image-pages.pdf") { assertEquals(3, it.pageCount) }
    }

    @Test
    fun pageSizeIsReportedInPointsSoBothPlatformsAgreeOnFit() {
        // The same numbers iOS asserts from the same manifest. This is the
        // cross-platform fit requirement, and it is exact rather than tolerant
        // because a page box is not a measurement.
        reader("text-pages.pdf") {
            assertEquals(PageSize(612, 792), it.sizePoints(0))
        }
        reader("image-pages.pdf") {
            assertEquals(PageSize(200, 300), it.sizePoints(0))
        }
    }

    @Test
    fun anImageOnlyPdfKeepsTheCorpusPageAspect() {
        reader("image-pages.pdf") {
            val size = it.sizePoints(0)
            // 2:3 portrait, the ratio every fixture page uses.
            assertEquals(2.0 / 3.0, size.width.toDouble() / size.height, 0.0001)
        }
    }

    @Test
    fun aPageRendersBoundedOnItsLongestEdgeAndNeverUpscales() {
        reader("image-pages.pdf") {
            val full = it.render(0)
            assertEquals(200, full.width)
            assertEquals(300, full.height)

            val bounded = it.render(0, maxPixelSize = 150)
            assertEquals(100, bounded.width)
            assertEquals(150, bounded.height)

            // Asking for more than the page has must not inflate it, matching
            // PageDecoder's contract for image pages.
            val oversized = it.render(0, maxPixelSize = 4000)
            assertEquals(200, oversized.width)
            assertEquals(300, oversized.height)
        }
    }

    @Test
    fun aRenderedImagePageCarriesThePixelsTheFixtureDrew() {
        reader("image-pages.pdf") {
            val bitmap = it.render(0)
            val centre = bitmap.getPixel(bitmap.width / 2, bitmap.height / 2)
            // The fixture fills page 1 with hue(1) = (37, 91, 151). Sampling
            // proves the page really rasterised rather than returning a blank
            // bitmap of the right size. iOS asserts the identical triple.
            assertEquals(37, android.graphics.Color.red(centre))
            assertEquals(91, android.graphics.Color.green(centre))
            assertEquals(151, android.graphics.Color.blue(centre))
        }
    }

    @Test
    fun aTextPdfStillRendersEvenThoughItsTextIsUnreachable() {
        // The `Text-based PDF on Android` scenario: the publication opens and
        // reads as images. Only the text layer is missing, not the page.
        reader("text-pages.pdf") {
            val bitmap = it.render(0, maxPixelSize = 400)
            assertEquals(400, maxOf(bitmap.width, bitmap.height))
            // The page is painted white before rendering, so a corner pixel is
            // opaque paper rather than transparent nothing.
            assertEquals(255, android.graphics.Color.alpha(bitmap.getPixel(2, 2)))
        }
    }

    @Test
    fun renderingIsOnDemandRatherThanUpFront() {
        // `ebook-reader` requires a several-hundred-megabyte PDF to render pages
        // as they are needed. Opening a document must therefore not rasterise:
        // the proof is that page count is available with no page opened, and any
        // single page can be rendered without touching the others.
        reader("image-pages.pdf") {
            assertEquals(3, it.pageCount)
            val last = it.render(2, maxPixelSize = 64)
            assertTrue(last.width in 1..64 && last.height in 1..64)
        }
    }

    @Test
    fun aPageIndexOutsideTheDocumentIsRefusedNotClamped() {
        reader("image-pages.pdf") { reader ->
            assertThrows(PdfException.PageOutOfRange::class.java) { reader.sizePoints(3) }
            assertThrows(PdfException.PageOutOfRange::class.java) { reader.render(-1) }
        }
    }

    @Test
    fun bytesThatAreNotAPdfAreRefused() {
        val context = InstrumentationRegistry.getInstrumentation().context
        val bogus = File(context.cacheDir, "not-a-pdf.pdf")
        bogus.writeBytes(ByteArray(1024) { 0x41 })
        assertThrows(PdfException.Unreadable::class.java) { PdfDocumentReader(bogus) }
    }
}
