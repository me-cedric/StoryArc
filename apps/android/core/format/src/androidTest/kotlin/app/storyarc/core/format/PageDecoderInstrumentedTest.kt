package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Closes the last *Assumed* row for Android image decoding in ADR-0005: not "the
 * API exists" but "a page from the shared corpus decodes to a bitmap of the
 * expected size, and downsampling actually downsamples".
 *
 * Instrumented rather than a JVM unit test because `ImageDecoder` and `Bitmap`
 * are framework classes that are stubs off-device. iOS's equivalent runs as a
 * plain unit test because ImageIO is available on the host — that asymmetry is in
 * the platforms, not in the coverage.
 *
 * The corpus is copied into the device's cache by the test, since it lives
 * outside the APK.
 */
@RunWith(AndroidJUnit4::class)
class PageDecoderInstrumentedTest {

    private fun fixture(name: String): File {
        // Fixtures are packaged as instrumentation assets by the build script and
        // copied out, because ZipReader needs a real seekable file.
        val context = InstrumentationRegistry.getInstrumentation().context
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    private fun firstPage(archive: String): ByteArray = runBlocking {
        ComicArchiveOpener.open(fixture(archive)).use { opened ->
            opened.data(opened.pages.first())
        }
    }

    @Test
    fun dimensionsComeFromTheHeaderWithoutDecodingThePixels() {
        val size = PageDecoder.dimensions(firstPage("comics/large-page.cbz"))

        assertEquals(2000, size.width)
        assertEquals(3000, size.height)
    }

    @Test
    fun aFullDecodeProducesThePageAtItsRealSize() {
        val bitmap = PageDecoder.decode(firstPage("comics/large-page.cbz"))

        assertEquals(2000, bitmap.width)
        assertEquals(3000, bitmap.height)
    }

    @Test
    fun downsamplingBoundsTheLongestEdgeAndKeepsTheAspectRatio() {
        val bitmap = PageDecoder.decode(firstPage("comics/large-page.cbz"), maxPixelSize = 600)

        // 2000x3000 constrained to 600 on the long edge -> 400x600.
        assertTrue(maxOf(bitmap.width, bitmap.height) <= 600)
        assertEquals(600, bitmap.height)
        assertEquals(400, bitmap.width)
    }

    @Test
    fun askingForMoreThanTheSourceHasDoesNotUpscale() {
        val bitmap = PageDecoder.decode(firstPage("comics/large-page.cbz"), maxPixelSize = 9000)

        assertTrue(bitmap.width <= 2000)
        assertTrue(bitmap.height <= 3000)
    }

    @Test
    fun aTinyPageStillDecodesSoTheSmallFixturesStayUsable() {
        val data = firstPage("comics/natural-sort.cbz")

        assertEquals(2, PageDecoder.dimensions(data).width)
        assertEquals(2, PageDecoder.decode(data).width)
    }

    @Test
    fun bytesThatAreNotAnImageAreReportedNotCrashedOn() {
        val junk = "this is not a picture".toByteArray()

        assertThrows(PageDecoder.UnrecognisedImageException::class.java) {
            PageDecoder.dimensions(junk)
        }
    }

    @Test
    fun aDoublePageSpreadIsDetectedFromItsAspectRatio() = runBlocking {
        ComicArchiveOpener.open(fixture("comics/double-page-spread.cbz")).use { opened ->
            val verdicts = opened.pages.map { page ->
                val size = PageDecoder.dimensions(opened.data(page))
                PageDecoder.isSpread(size.width, size.height)
            }
            // The manifest records index 1 as the spread; the others are portrait.
            assertEquals(listOf(false, true, false), verdicts)
        }
    }
}
