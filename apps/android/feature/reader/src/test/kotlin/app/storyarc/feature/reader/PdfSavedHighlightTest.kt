package app.storyarc.feature.reader

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.format.PdfLocator
import app.storyarc.core.format.PdfTextPoint
import app.storyarc.core.format.PdfTextReading
import app.storyarc.core.format.PdfTextRect
import app.storyarc.core.format.PdfTextSelection
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.HighlightColour
import app.storyarc.core.persistence.AnnotationStore
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Task 23.1 -- a saved highlight is on the PDF page that holds it.
 *
 * The Highlights list read the store and showed the mark. The page read `PdfTextState.marks`,
 * which stayed empty because nothing resolved a page's marks into rectangles, so no transition
 * mode drew one. This builds the state the reader builds, with a text reader that answers one
 * run of words, draws the page through the composable the page composable calls, and asks for
 * the page's decoration the way the page composable does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PdfSavedHighlightTest {

    @get:Rule
    val compose = createComposeRule()

    private val words = PdfTextRect(0.1f, 0.2f, 0.5f, 0.03f)

    private fun state(
        vararg saved: Annotation,
        reader: PdfTextReading = OneRunReader(PdfTextSelection(PdfLocator(PAGE, 4, 12), "the words", listOf(words))),
    ): PdfTextState {
        val store = AnnotationStore.open(RuntimeEnvironment.getApplication())
        saved.forEach { store.save(it, PUBLICATION) }
        return PdfTextState(
            reader = reader,
            store = store,
            publication = PUBLICATION,
            title = "Fixture",
            pageCount = 5,
        ).also { it.load() }
    }

    private fun annotation(page: Int, colour: HighlightColour = HighlightColour.GREEN) = Annotation(
        id = "mark-$page",
        locator = PdfLocator(page, 4, 12).json,
        resource = (page + 1).toString(),
        progression = page / 5.0,
        chapter = "Page ${page + 1}",
        text = "the words",
        colour = colour,
        createdAtEpochMillis = 1L,
    )

    @Test
    fun `a saved highlight reaches the draw list of the page that holds it`() {
        val text = state(annotation(PAGE))
        compose.setContent { ResolvePageMarks(text, PAGE) }
        // The marks resolve on Dispatchers.IO, which `waitForIdle` does not wait for.
        compose.waitUntil(timeoutMillis = 5_000) { text.marks.value.containsKey(PAGE) }

        val decoration = pdfDecorationOn(PAGE, hasText = true, marks = text.marks.value, selection = null)
        assertEquals("the saved highlight is not in the page's draw list", 1, decoration.marks.size)
        assertEquals(HighlightColour.GREEN, decoration.marks.single().colour)
        assertEquals(words, decoration.marks.single().rect)
    }

    @Test
    fun `two pages drawn at once both keep their highlights`() {
        // A spread, a scroll and a pager all compose more than one page at a time, so two
        // pages resolve together. Neither may overwrite the other's marks.
        val text = state(annotation(PAGE), annotation(OTHER_PAGE), reader = AnyPageReader(words))
        compose.setContent {
            ResolvePageMarks(text, PAGE)
            ResolvePageMarks(text, OTHER_PAGE)
        }
        compose.waitUntil(timeoutMillis = 5_000) { text.marks.value.keys.containsAll(listOf(PAGE, OTHER_PAGE)) }

        listOf(PAGE, OTHER_PAGE).forEach { page ->
            val drawn = pdfDecorationOn(page, hasText = true, marks = text.marks.value, selection = null).marks
            assertEquals("page $page lost its saved highlight to the other page", 1, drawn.size)
        }
    }

    @Test
    fun `a page that holds no highlight draws none`() {
        val text = state(annotation(PAGE))
        compose.setContent { ResolvePageMarks(text, OTHER_PAGE) }
        compose.waitForIdle()

        assertTrue(pdfDecorationOn(OTHER_PAGE, hasText = true, marks = text.marks.value, selection = null).marks.isEmpty())
    }

    @Test
    fun `a highlight made on a page that was never resolved is drawn at once`() {
        val text = state()
        val selection = PdfTextSelection(PdfLocator(PAGE, 4, 12), "the words", listOf(words))
        runBlocking {
            text.select(PAGE, PdfTextPoint(0.1f, 0.2f), PdfTextPoint(0.6f, 0.2f))
            text.highlight(HighlightColour.PINK, "Page 3")
        }

        val drawn = pdfDecorationOn(PAGE, hasText = true, marks = text.marks.value, selection = null).marks
        assertEquals(selection.rects, drawn.map { it.rect })
        assertEquals(HighlightColour.PINK, drawn.single().colour)
    }

    @Test
    fun `the page composable resolves the marks of the page it draws`() {
        val source = readerScreenSource(File(androidRoot, "feature/reader"))
        assertTrue(
            "SinglePage no longer resolves its page's marks, so no saved highlight is drawn.",
            source.contains("ResolvePageMarks(pdfText, index)"),
        )
        assertTrue(
            "pdfDecoration no longer asks pdfDecorationOn, so the page draws something other than the draw list.",
            source.contains("pdfDecorationOn(index, pdfText != null, pdfMarks, pdfSelection)"),
        )
    }

    /** A text reader with one run of words, found again whenever its page is asked for. */
    private class OneRunReader(private val run: PdfTextSelection) : PdfTextReading {
        override val pageCount = 5
        override val hasTextLayer = true
        override fun text(index: Int): String? = null
        override fun selection(index: Int, from: PdfTextPoint, to: PdfTextPoint) = run
        override fun selection(locator: PdfLocator) = run.takeIf { locator.page == it.locator.page }
        override fun close() = Unit
    }

    /** A text reader that finds the same words on every page it is asked about. */
    private class AnyPageReader(private val rect: PdfTextRect) : PdfTextReading {
        override val pageCount = 5
        override val hasTextLayer = true
        override fun text(index: Int): String? = null
        override fun selection(index: Int, from: PdfTextPoint, to: PdfTextPoint) =
            PdfTextSelection(PdfLocator(index, 4, 12), "the words", listOf(rect))
        override fun selection(locator: PdfLocator) = PdfTextSelection(locator, "the words", listOf(rect))
        override fun close() = Unit
    }

    private companion object {
        const val PUBLICATION = "fixture-pdf"
        const val PAGE = 2
        const val OTHER_PAGE = 3

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("No settings.gradle.kts above ${File("").absolutePath}.")
    }
}
