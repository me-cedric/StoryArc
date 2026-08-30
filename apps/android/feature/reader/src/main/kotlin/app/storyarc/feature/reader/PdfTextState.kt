package app.storyarc.feature.reader

import app.storyarc.core.format.PdfLocator
import app.storyarc.core.format.PdfTextPoint
import app.storyarc.core.format.PdfTextReading
import app.storyarc.core.format.PdfTextSearch
import app.storyarc.core.format.PdfTextSelection
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.HighlightColour
import app.storyarc.core.model.SearchMatch
import app.storyarc.core.persistence.AnnotationStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * The text side of a PDF: what is selected, what is marked, and what a search found.
 *
 * Its own holder rather than more state on [ReaderViewModel], and for two reasons. The view model
 * is the *pages* -- the window of decoded bitmaps, the fit, the turn -- and none of that changes
 * for a PDF that happens to carry text. And this exists only when there is text: a scanned comic
 * never builds one, which is what makes the absence of the controls structural rather than a flag
 * checked in every composable.
 *
 * `ebook-reader`: a PDF that "contains a text layer" gets selection and in-publication search. The
 * document outline is the one part of that scenario this platform cannot answer -- the PDF API
 * exposes links and text and no outline -- which ADR-0012 records.
 *
 * Its own [Mutex], not the view model's: the text reader holds a second document handle, so a
 * selection has no reason to wait behind a page render.
 *
 * iOS's `PdfTextModel` holds the same state.
 */
internal class PdfTextState(
    private val reader: PdfTextReading,
    private val store: AnnotationStore?,
    private val publication: String,
    /** What the export document is headed with. */
    val title: String,
    private val pageCount: Int,
) {
    private val lock = Mutex()

    private val _annotations = MutableStateFlow<List<Annotation>>(emptyList())

    /** Everything the reader has marked in this publication, in reading order. */
    val annotations: StateFlow<List<Annotation>> = _annotations.asStateFlow()

    private val _marks = MutableStateFlow<Map<Int, List<PdfPageMark>>>(emptyMap())

    /**
     * The marks resolved to rectangles, per page, as pages come into view.
     *
     * Resolved lazily and kept: turning a locator back into rectangles opens the page in the PDF
     * module, and doing that for four hundred marks when the reader opens the book would cost the
     * whole document to draw three highlights.
     */
    val marks: StateFlow<Map<Int, List<PdfPageMark>>> = _marks.asStateFlow()

    private val _selection = MutableStateFlow<PdfTextSelection?>(null)

    /** What the reader has selected right now, or nothing. */
    val selection: StateFlow<PdfTextSelection?> = _selection.asStateFlow()

    private val _matches = MutableStateFlow<List<SearchMatch>>(emptyList())
    val matches: StateFlow<List<SearchMatch>> = _matches.asStateFlow()

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private val _isCapped = MutableStateFlow(false)

    /** Whether the run stopped at the cap rather than at the end of the document. */
    val isCapped: StateFlow<Boolean> = _isCapped.asStateFlow()

    private var searchGeneration = 0
    private var selectionGeneration = 0

    /** Reads what is stored. Called once, when the reader opens. */
    fun load() {
        _annotations.value = store?.annotations(publication).orEmpty()
    }

    // Marks on the page

    /** Turns this page's stored marks into rectangles, if it has not already. */
    suspend fun resolveMarks(page: Int) {
        if (_marks.value.containsKey(page)) return
        _marks.value = _marks.value + (page to rects(page))
    }

    private suspend fun rects(page: Int): List<PdfPageMark> = withContext(Dispatchers.IO) {
        lock.withLock {
            _annotations.value.flatMap { annotation ->
                val locator = PdfLocator.of(annotation.locator)
                if (locator == null || locator.page != page) return@flatMap emptyList()
                val resolved = reader.selection(locator) ?: return@flatMap emptyList()
                resolved.rects.map { PdfPageMark(annotation.id, it, annotation.colour) }
            }
        }
    }

    /** Draws every page's marks again, because one of them changed. */
    private suspend fun redraw() {
        _marks.value = _marks.value.keys.associateWith { rects(it) }
    }

    // Selecting

    /**
     * Selects what lies between two points, both normalised to the page.
     *
     * A drag asks for one of these per movement and each waits on the reader, so the answers
     * can arrive in a different order from the questions. The generation is what stops an older
     * answer landing on top of a newer one and leaving the mark a few words behind the finger.
     */
    suspend fun select(page: Int, from: PdfTextPoint, to: PdfTextPoint) {
        selectionGeneration += 1
        val generation = selectionGeneration
        val found = withContext(Dispatchers.IO) {
            lock.withLock { reader.selection(page, from, to) }
        }
        if (generation != selectionGeneration) return
        _selection.value = found
    }

    fun clearSelection() {
        // Bumped, so a selection still in flight does not arrive after the reader dropped it.
        selectionGeneration += 1
        _selection.value = null
    }

    // Marking

    /**
     * Marks the current selection in a colour, and hands back the mark it made.
     *
     * Handed back rather than looked up again, because writing a note on it is the very next
     * thing a reader may do and a list search for "the one just added" is a lookup by luck.
     */
    suspend fun highlight(colour: HighlightColour, chapter: String): Annotation? {
        val store = store ?: return null
        val selection = _selection.value ?: return null
        val mark = Annotation(
            id = UUID.randomUUID().toString(),
            locator = selection.locator.json,
            resource = (selection.locator.page + 1).toString(),
            progression =
                if (pageCount > 0) selection.locator.page.toDouble() / pageCount else 0.0,
            chapter = chapter,
            text = selection.text,
            colour = colour,
            createdAtEpochMillis = System.currentTimeMillis(),
        )
        _annotations.value = store.save(mark, publication)
        clearSelection()
        redraw()
        return mark
    }

    /** Writes on a mark, or replaces what was written. */
    suspend fun annotate(annotation: Annotation, note: String) {
        val store = store ?: return
        _annotations.value = store.save(annotation.copy(note = note), publication)
        redraw()
    }

    suspend fun remove(id: String) {
        val store = store ?: return
        _annotations.value = store.remove(id, publication)
        redraw()
    }

    /** The page a mark is on, so tapping its row turns there. */
    fun page(annotation: Annotation): Int? = PdfLocator.of(annotation.locator)?.page

    /** The page a hit is on, so tapping its row turns there. */
    fun page(match: SearchMatch): Int? = PdfLocator.of(match.locator)?.page

    // Searching

    /**
     * Searches the whole publication, page by page.
     *
     * A page at a time rather than the document at once, and that is not an optimisation: the
     * text reader permits one open page, so a walk that held it for the length of a
     * five-hundred-page document would stall every selection behind it. Between pages the reader
     * can turn, and the results arrive as they are found -- a reader looking for a word they know
     * is on page nine should not wait for page four hundred.
     *
     * A new search replaces the one before it. The field is searched as it is typed, and a
     * previous query still filling the list would put its results under the new one's.
     */
    suspend fun search(query: String, chapter: (Int) -> String) {
        searchGeneration += 1
        val generation = searchGeneration

        val trimmed = query.trim()
        if (trimmed.isEmpty()) {
            _matches.value = emptyList()
            _isSearching.value = false
            _isCapped.value = false
            return
        }

        _matches.value = emptyList()
        _isCapped.value = false
        _isSearching.value = true

        val found = mutableListOf<SearchMatch>()
        for (page in 0 until reader.pageCount) {
            if (generation != searchGeneration) return
            if (found.size >= PdfTextSearch.MATCH_LIMIT) {
                _isCapped.value = true
                break
            }
            val text = withContext(Dispatchers.IO) { lock.withLock { reader.text(page) } }
                ?: continue
            if (generation != searchGeneration) return

            val label = chapter(page)
            found += PdfTextSearch.matches(
                text = text,
                page = page,
                query = trimmed,
                limit = PdfTextSearch.MATCH_LIMIT - found.size,
            ).map { hit ->
                SearchMatch(locator = hit.locator.json, chapter = label, snippet = hit.snippet)
            }
            _matches.value = found.toList()
        }
        if (generation == searchGeneration) _isSearching.value = false
    }

    fun close() {
        reader.close()
    }
}
