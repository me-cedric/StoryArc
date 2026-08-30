package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The text layer, asserted against the shared corpus in `packages/test-fixtures`.
 *
 * Mirrors the selection and search half of iOS's `PdfDocumentReaderTests`, case for case. The
 * document outline is not here and is not missing: PDFKit reads one and the platform's PDF API
 * exposes none, which ADR-0012 records.
 *
 * Instrumented rather than a JVM unit test because the PDF text API is a framework class that
 * is a stub off-device -- the same reason `PdfDocumentReaderInstrumentedTest` is instrumented.
 *
 * Every test opens with an assumption rather than a check, because the capability ships in a
 * mainline module: on a device or image without it there is nothing to assert and nothing
 * broken, and a failure there would report the emulator rather than the code.
 */
@RunWith(AndroidJUnit4::class)
class PdfTextReaderInstrumentedTest {

    private fun fixture(name: String): File {
        // The corpus is packaged as instrumentation assets by the build script and copied out,
        // because the PDF reader needs a real seekable file descriptor.
        val context = InstrumentationRegistry.getInstrumentation().context
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    private fun <T> reader(name: String, block: (PdfTextReading) -> T): T {
        assumeTrue("no PDF text API on this device", PdfTextReading.isSupported)
        val opened = requireNotNull(PdfTextReading.open(fixture("comics/$name"))) {
            "the corpus PDF opened for reading but not for text"
        }
        return opened.use(block)
    }

    @Test
    fun aTextLayerIsDetectedRatherThanAssumedFromTheExtension() {
        reader("text-pages.pdf") { assertTrue(it.hasTextLayer) }
        // The scanned-comic case. `ebook-reader` forbids offering selection or search when
        // there is no text to find, on either platform.
        reader("image-pages.pdf") { assertTrue(!it.hasTextLayer) }
    }

    @Test
    fun eachPagesTextMatchesTheManifest() {
        val expected = listOf("Chapter One", "Chapter Two", "Chapter Three")
        reader("text-pages.pdf") {
            expected.forEachIndexed { index, text -> assertEquals(text, it.text(index)?.trim()) }
        }
    }

    @Test
    fun anImageOnlyPdfYieldsNoTextOnAnyPage() {
        reader("image-pages.pdf") {
            for (index in 0 until it.pageCount) assertNull(it.text(index))
        }
    }

    @Test
    fun aPagesTextIsWhatTheSearchRuleIsAppliedTo() {
        reader("text-pages.pdf") {
            val page = requireNotNull(it.text(1))
            val found = PdfTextSearch.matches(page, page = 1, query = "chapter two")
            // Case-insensitive, because a reader's search box is not a grep.
            assertEquals(1, found.size)
            assertEquals("Chapter Two", found.first().snippet.line)
            assertTrue(PdfTextSearch.matches(page, page = 1, query = "Chapter Three").isEmpty())
        }
    }

    @Test
    fun aDragAcrossAPageSelectsTheWordsItCrossed() {
        reader("text-pages.pdf") {
            val selected =
                requireNotNull(it.selection(0, PdfTextPoint(0f, 0f), PdfTextPoint(1f, 1f)))
            assertEquals("Chapter One", selected.text.trim())
            assertEquals(0, selected.locator.page)
            assertTrue(selected.locator.end > selected.locator.start)
            assertTrue(selected.rects.isNotEmpty())
        }
    }

    @Test
    fun selectionRectanglesAreNormalisedSoTheReaderCanDrawThemOverAnyRaster() {
        reader("text-pages.pdf") {
            val selected =
                requireNotNull(it.selection(0, PdfTextPoint(0f, 0f), PdfTextPoint(1f, 1f)))
            for (rect in selected.rects) {
                assertTrue(rect.x >= 0f && rect.x + rect.width <= 1f)
                assertTrue(rect.y >= 0f && rect.y + rect.height <= 1f)
                assertTrue(rect.width > 0f && rect.height > 0f)
            }
            // The fixture writes one line near the top of the page, so the mark belongs there
            // rather than in the middle -- which is what proves the page's own coordinate
            // origin was accounted for.
            assertTrue(selected.rects.minOf { rect -> rect.y } < 0.5f)
        }
    }

    @Test
    fun aPressWithNoDragTakesTheWordUnderIt() {
        reader("text-pages.pdf") {
            // Inside the fixture's own line: 24pt type with its baseline at 700 on a
            // 792-point page, so a tenth of the way down is on the glyphs.
            val point = PdfTextPoint(0.15f, 0.1f)
            val word = requireNotNull(it.selection(0, point, point))
            assertTrue(word.text.isNotEmpty())
            assertTrue("Chapter One".contains(word.text.trim()))
        }
    }

    @Test
    fun aSelectionIsFoundAgainFromTheLocatorItWasStoredUnder() {
        reader("text-pages.pdf") {
            val selected =
                requireNotNull(it.selection(1, PdfTextPoint(0f, 0f), PdfTextPoint(1f, 1f)))
            val again = requireNotNull(it.selection(selected.locator))
            assertEquals(selected.text, again.text)
            assertEquals(selected.locator, again.locator)
        }
    }

    @Test
    fun aDragOverAPageWithNoTextSelectsNothingRatherThanAnEmptyRun() {
        reader("image-pages.pdf") {
            assertNull(it.selection(0, PdfTextPoint(0f, 0f), PdfTextPoint(1f, 1f)))
        }
    }

    @Test
    fun aLocatorNamingAPageTheDocumentDoesNotHaveSelectsNothing() {
        reader("text-pages.pdf") {
            assertNull(it.selection(PdfLocator(page = 9, start = 0, end = 4)))
        }
    }
}
