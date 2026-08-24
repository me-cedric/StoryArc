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

    // Cross-platform agreement.

    @Test
    fun aDecodedPageCarriesTheExactPixelsTheFixtureDrew() {
        val expected = manifestPixel()
        val bitmap = PageDecoder.decode(firstPage("comics/large-page.cbz"))
        val centre = bitmap.getPixel(bitmap.width / 2, bitmap.height / 2)

        // Exact, with no tolerance. The fixture page is one flat colour, so a
        // full-size decode has nothing to interpolate — any difference here would
        // be a colour-space conversion, not resampling. iOS's `PageDecoderTests`
        // asserts the same three numbers from the same manifest entry, which is
        // what makes the two decoders comparable at all.
        assertEquals(expected[0], android.graphics.Color.red(centre))
        assertEquals(expected[1], android.graphics.Color.green(centre))
        assertEquals(expected[2], android.graphics.Color.blue(centre))
    }

    @Test
    fun downsamplingKeepsTheColourWithinOneStepPerChannel() {
        val expected = manifestPixel()
        val bitmap = PageDecoder.decode(firstPage("comics/large-page.cbz"), maxPixelSize = 600)
        val centre = bitmap.getPixel(bitmap.width / 2, bitmap.height / 2)

        // **The recorded tolerance: plus or minus 1 per channel.** ImageDecoder
        // and ImageIO are different resamplers, so their rounding at a 5:1
        // reduction is not required to agree bit for bit. On a flat colour the
        // honest bound is one step; anything wider would hide a real difference
        // and anything narrower would assert an implementation detail of one
        // platform.
        assertTrue(
            "red off by more than 1",
            Math.abs(android.graphics.Color.red(centre) - expected[0]) <= 1,
        )
        assertTrue(
            "green off by more than 1",
            Math.abs(android.graphics.Color.green(centre) - expected[1]) <= 1,
        )
        assertTrue(
            "blue off by more than 1",
            Math.abs(android.graphics.Color.blue(centre) - expected[2]) <= 1,
        )
    }

    /**
     * The expected pixel, read from the shared manifest rather than hard-coded, so
     * the two platforms cannot drift apart by editing one file.
     */
    private fun manifestPixel(): List<Int> {
        val context = InstrumentationRegistry.getInstrumentation().context
        val text = context.assets.open("manifest.json").bufferedReader().use { it.readText() }
        val at = text.indexOf("\"expectedPagePixel\"")
        assertTrue("manifest has no expectedPagePixel", at > 0)
        val open = text.indexOf('[', at)
        val close = text.indexOf(']', open)
        return text.substring(open + 1, close).split(',').map { it.trim().toInt() }
    }
}
