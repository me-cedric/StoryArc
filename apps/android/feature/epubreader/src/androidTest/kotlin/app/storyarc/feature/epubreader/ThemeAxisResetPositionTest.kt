package app.storyarc.feature.epubreader

import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.sliderRange
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFragment

/**
 * `reader-theming-and-page-transitions` 3.5: a reader who changes an axis and then resets it is
 * on the same paragraph afterwards.
 *
 * `ThemeAxisResetTest` proves what `resetAxis` asks of the view model, and pins the source order
 * of the reset, because no JVM test can lay out a navigator. This is the behaviour, on a real
 * reflowable book in the real activity: turn to a page in the middle of a chapter, move the
 * margins, reset them through the same `resetAxis` the slider's long press calls, and check
 * after each step that the first paragraph of the starting page is still on the page.
 *
 * `ebook-reader`: "the reading position is preserved to the paragraph, not the page number".
 * Submitting preferences re-paginates the resource and Readium lands on the progression, which
 * measured on an emulator moved the reader fourteen paragraphs back inside one chapter. The
 * activity's `applyTheme` goes back to the locator it captured.
 *
 * **This case does not catch the removal of that `navigator.go` call.** Measured on 2026-10-10
 * on the `storyarc-ci` emulator (API 35): with the call removed, Readium's own landing kept the
 * paragraph on the page, and the case passed. A book with paragraphs of mixed length did the
 * same. `currentLocator` holds a progression and no text, so the call goes to the same
 * progression that Readium lands on by itself.
 *
 * The book is written here, forty paragraphs a chapter and each reading "Chapter 1, paragraph
 * 31." as `packages/test-fixtures/ebooks/fixture.epub` does, so the test needs nothing on the
 * device. The long press itself is a Compose gesture on the axes screen and is not driven here:
 * `resetAxis` is what that gesture calls, and iOS's `ThemeAxisResetUITests` presses the slider.
 *
 * iOS's `ThemeAxisResetUITests` is the mirror.
 */
@RunWith(AndroidJUnit4::class)
class ThemeAxisResetPositionTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context: Context get() = instrumentation.targetContext

    @Test
    fun theReaderStaysOnItsParagraphThroughAnAxisChangeAndItsReset() {
        val book = writeBook()
        val intent = EpubReaderActivity.intent(context, book.absolutePath, "Axis reset fixture", series = null)

        ActivityScenario.launch<EpubReaderActivity>(intent).use { scenario ->
            var navigator: EpubNavigatorFragment? = null
            waitFor("the navigator to appear") {
                scenario.onActivity { navigator = it.supportFragmentManager.findFragmentByTag(NAVIGATOR_TAG) as? EpubNavigatorFragment }
                navigator != null && firstParagraph(navigator!!) != null
            }
            val reader = navigator!!

            // A page in the middle of a chapter, so there is somewhere to drift from.
            var turns = 0
            while ((firstParagraph(reader) ?: 0) < MID_CHAPTER && turns < MAX_TURNS) {
                runBlocking(Dispatchers.Main) { reader.goForward(animated = false) }
                settle()
                turns++
            }
            val before = firstParagraph(reader)
            assertNotNull("No paragraph is readable on the page.", before)
            assertTrue("No page in the middle of a chapter in $turns turns; the page begins at $before.", before!! >= MID_CHAPTER)

            // Margins, the axis that reflows the most: a narrower column puts far fewer words on
            // a page, so a reader landing by progression alone is many paragraphs away.
            val widest = ThemeAxis.MARGINS.sliderRange!!.endInclusive
            scenario.onActivity { it.model.set(ThemeAxis.MARGINS, widest) }
            settle()
            assertOnPage("Changing an axis moved the reader off its paragraph.", before, paragraphsOnPage(reader))

            scenario.onActivity { activity ->
                resetAxis(activity.model.theme.value.preset, ThemeAxis.MARGINS, activity.model::set)
            }
            settle()
            assertOnPage("Resetting an axis moved the reader off its paragraph.", before, paragraphsOnPage(reader))
        }
    }

    /**
     * The paragraph is still on the page, wherever on it.
     *
     * Not the first paragraph of the page: a reflow moves every page break, so the page that
     * holds paragraph 14 can begin with the tail of paragraph 10. Measured on 2026-10-10 on the
     * `storyarc-ci` emulator: wide margins put paragraphs 10 to 21 on that page, with 14 in the
     * middle of it, and a first-paragraph comparison called that a drift of four.
     */
    private fun assertOnPage(message: String, expected: Int, shown: List<Int>) {
        assertTrue("$message Paragraph $expected is not on the page, which shows $shown.", expected in shown)
    }

    /** Long enough for Readium to re-paginate and for the activity's own settle delay to pass. */
    private fun settle() = Thread.sleep(SETTLE_MILLIS)

    private fun waitFor(what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return
            Thread.sleep(POLL_MILLIS)
        }
        throw AssertionError("Timed out waiting for $what.")
    }

    private fun firstParagraph(navigator: EpubNavigatorFragment): Int? = paragraphsOnPage(navigator).firstOrNull()

    /**
     * The numbers of the paragraphs on the page, in order, read from the page itself.
     *
     * Asked of the web view that is showing, in the page's own terms: a paragraph is on the
     * page when its box meets the viewport, whichever column of the chapter it sits in.
     */
    private fun paragraphsOnPage(navigator: EpubNavigatorFragment): List<Int> {
        val view = navigator.view ?: return emptyList()
        val shown = arrayListOf<WebView>()
        instrumentation.runOnMainSync { collectShownWebViews(view, shown) }
        for (web in shown) {
            val latch = CountDownLatch(1)
            var answer: String? = null
            instrumentation.runOnMainSync {
                web.evaluateJavascript(PARAGRAPHS_SCRIPT) {
                    answer = it
                    latch.countDown()
                }
            }
            if (!latch.await(JS_TIMEOUT_SECONDS, TimeUnit.SECONDS)) continue
            val numbers = answer?.trim('"')?.split(',')?.mapNotNull { it.toIntOrNull() }.orEmpty()
            if (numbers.isNotEmpty()) return numbers
        }
        return emptyList()
    }

    private fun collectShownWebViews(view: View, into: MutableList<WebView>) {
        if (view is WebView && view.isShown && view.width > 0) into += view
        if (view is ViewGroup) for (index in 0 until view.childCount) collectShownWebViews(view.getChildAt(index), into)
    }

    /** A reflowable book of two chapters, each of forty paragraphs, in the cache directory. */
    private fun writeBook(): File {
        val file = File(context.cacheDir, "axis-reset-fixture.epub")
        file.delete()
        ZipOutputStream(file.outputStream()).use { zip ->
            val mimetype = "application/epub+zip".toByteArray()
            zip.putNextEntry(
                ZipEntry("mimetype").apply {
                    method = ZipEntry.STORED
                    size = mimetype.size.toLong()
                    compressedSize = size
                    crc = CRC32().also { it.update(mimetype) }.value
                },
            )
            zip.write(mimetype)
            zip.closeEntry()
            fun add(name: String, text: String) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
            add("META-INF/container.xml", CONTAINER)
            add("OEBPS/package.opf", PACKAGE)
            add("OEBPS/nav.xhtml", NAV)
            add("OEBPS/ch1.xhtml", chapter(1))
            add("OEBPS/ch2.xhtml", chapter(2))
        }
        return file
    }

    private fun chapter(number: Int): String {
        val paragraphs = (1..PARAGRAPHS).joinToString("\n") {
            "    <p>Chapter $number, paragraph $it. Text long enough that pagination has something to do with it.</p>"
        }
        return """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter $number</title></head>
<body>
    <h1>Chapter $number</h1>
$paragraphs
</body>
</html>
"""
    }

    private companion object {
        const val NAVIGATOR_TAG = "epub-navigator"
        const val PARAGRAPHS = 40
        const val MID_CHAPTER = 10
        const val MAX_TURNS = 30
        const val SETTLE_MILLIS = 1_500L
        const val POLL_MILLIS = 250L
        const val TIMEOUT_MILLIS = 30_000L
        const val JS_TIMEOUT_SECONDS = 5L

        const val PARAGRAPHS_SCRIPT =
            "(function(){var ps=document.querySelectorAll('p');var shown=[];" +
                "for(var i=0;i<ps.length;i++){var r=ps[i].getBoundingClientRect();" +
                "if(r.right>0&&r.left<window.innerWidth&&r.bottom>0&&r.top<window.innerHeight){" +
                "var m=/paragraph (\\d+)/.exec(ps[i].textContent);if(m)shown.push(m[1]);}}return shown.join(',');})()"

        const val CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

        const val PACKAGE = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:storyarc-axis-reset-0001</dc:identifier>
    <dc:title>Axis reset fixture</dc:title>
    <dc:language>en</dc:language>
    <dc:creator>StoryArc Fixtures</dc:creator>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>
</package>"""

        const val NAV = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body><nav epub:type="toc"><ol>
  <li><a href="ch1.xhtml">Chapter One</a></li>
  <li><a href="ch2.xhtml">Chapter Two</a></li>
</ol></nav></body>
</html>"""
    }
}
