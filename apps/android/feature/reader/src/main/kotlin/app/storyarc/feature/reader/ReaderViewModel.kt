package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.snapshots.SnapshotStateSet
import androidx.compose.runtime.mutableStateSetOf
import androidx.lifecycle.ViewModel
import app.storyarc.core.format.ComicArchiveOpener
import app.storyarc.core.format.ComicArchiveReading
import app.storyarc.core.format.PageDecoder
import app.storyarc.core.format.PageEntry
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * One publication, open for reading.
 *
 * Holds the page list, the current position, and a small window of decoded pages.
 * `comic-reader` requires a turn to be immediate, which means the next page has to
 * be decoded before it is asked for — so this keeps neighbours warm and drops what
 * has scrolled away.
 *
 * iOS's `ReaderModel` is the same shape.
 */
class ReaderViewModel(
    val publication: Publication,
    private val file: File,
    private val progress: ProgressStore? = null,
) : ViewModel() {

    private val _pages = MutableStateFlow<List<PageEntry>>(emptyList())
    val pages: StateFlow<List<PageEntry>> = _pages.asStateFlow()

    private val _failure = MutableStateFlow<String?>(null)
    val failure: StateFlow<String?> = _failure.asStateFlow()

    /**
     * How many pages either side of the current one to keep decoded.
     *
     * One is enough to make a turn instant in both directions and small enough
     * that a corpus of 2000x3000 scans does not sit in memory.
     * `publication-formats` requires decoding not to exhaust memory regardless of
     * source image size.
     */
    private val window = 1

    /**
     * Decoded pages, in a state map rather than a plain one.
     *
     * Compose does not observe a `mutableMapOf`, so filling it recomposes nothing
     * and every page sits on its spinner for ever. iOS gets this from `@Observable`
     * tracking the property; Kotlin has to say it.
     */
    private val decoded = mutableStateMapOf<Int, Bitmap>()
    private val attempted = mutableStateSetOf<Int>()
    private var archive: ComicArchiveReading? = null
    private var maxPixelSize = 2048

    /**
     * The direction the reader turns pages in.
     *
     * From the publication, which took it from `ComicInfo` or the language. The
     * reader never guesses it separately — a manga that opens left-to-right on one
     * screen and right-to-left on another is worse than either.
     */
    val readingDirection: ReadingDirection get() = publication.readingDirection

    /** Where to open. A ComicInfo cover that is not page one starts there. */
    var initialIndex: Int = 0
        private set

    suspend fun open(maxPixelSize: Int) {
        this.maxPixelSize = maxPixelSize
        try {
            val opened = withContext(Dispatchers.IO) { ComicArchiveOpener.open(file) }
            archive = opened
            _pages.value = opened.pages
            publication.coverPath?.let { path ->
                val index = opened.pages.indexOfFirst { it.path == path }
                if (index >= 0) initialIndex = index
            }
            // A recorded position wins over the cover. `reading-progress` is about
            // picking up where you left off, and a book you are halfway through
            // should not reopen at its cover.
            val recorded = progress?.progress(publication.identity)?.position
            if (recorded is ReadingPosition.Page && recorded.index in opened.pages.indices) {
                initialIndex = recorded.index
            }
        } catch (cause: Exception) {
            _failure.value = cause.message ?: "could not be opened"
        }
    }

    fun image(index: Int): Bitmap? = decoded[index]

    /** Whether a page failed to decode, as opposed to not being ready yet. */
    fun isUnavailable(index: Int): Boolean = index in attempted && decoded[index] == null

    /**
     * Writes the position down.
     *
     * Every turn, not on leaving: ADR-0006 makes the local store authoritative, and
     * a reader that only saves on a clean exit loses the evening when the app is
     * killed in the background — which is the normal way a phone closes an app.
     *
     * The last page marks the publication finished. Finished is sticky, so turning
     * back afterwards does not unmark it.
     */
    private suspend fun record(index: Int) {
        val store = progress ?: return
        val total = _pages.value.size
        if (total == 0) return
        store.save(
            ReadingProgress(
                identity = publication.identity,
                position = ReadingPosition.Page(index, total),
                isFinished = index == total - 1,
                updatedAtEpochMillis = System.currentTimeMillis(),
            ),
        )
    }

    /** Decodes the page at [index] and its neighbours, and drops the rest. */
    suspend fun warm(index: Int) {
        record(index)
        val pages = _pages.value
        val wanted = ((index - window)..(index + window)).filter { it in pages.indices }.toSet()
        // Dropped before decoding, so peak memory is the window and not the window
        // plus whatever was there before.
        (decoded.keys - wanted).forEach {
            decoded.remove(it)
            attempted.remove(it)
        }
        // The current page first: a turn should not wait on its neighbours.
        for (target in listOf(index) + wanted.sortedBy { kotlin.math.abs(it - index) }) {
            if (target !in pages.indices || target in attempted) continue
            attempted += target
            decode(target, pages[target])
        }
    }

    private suspend fun decode(index: Int, page: PageEntry) {
        val opened = archive ?: return
        val bitmap = withContext(Dispatchers.IO) {
            runCatching { PageDecoder.decode(opened.data(page), maxPixelSize) }.getOrNull()
        }
        if (bitmap != null) decoded[index] = bitmap
    }

    override fun onCleared() {
        archive?.close()
        decoded.clear()
    }
}
