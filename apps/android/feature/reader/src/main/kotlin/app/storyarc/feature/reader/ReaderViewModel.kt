package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.snapshots.SnapshotStateSet
import androidx.compose.runtime.mutableStateSetOf
import androidx.lifecycle.ViewModel
import android.content.ContentResolver
import android.os.Build
import android.provider.Settings
import app.storyarc.core.format.ComicArchiveReading
import app.storyarc.core.format.PageDecoder
import app.storyarc.core.format.PageEntry
import app.storyarc.core.format.PdfDocumentReader
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.scrollAlong
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

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
    private val resolver: ContentResolver,
    /**
     * Where the publication lives, as its identity records it: a filesystem path,
     * or a document `Uri` from a folder the user picked.
     */
    private val path: String,
    private val progress: ProgressStore? = null,
    /**
     * Where the reading mode is remembered between sessions. Null in a preview.
     *
     * `comic-reader`'s mode persistence is word for word `reading-themes`' theme
     * persistence — per series, with a global default, and comics independent of
     * reflowable — so it is the same store.
     */
    private val shelfStore: ReaderPreferences? = null,
    /**
     * Whether this device can render the curl.
     *
     * API 33 is where AGSL's `RuntimeShader` arrives, and ADR-0003 keeps the floor at
     * 31 rather than raising it for one animation. `page-transitions` already required
     * Curl to be absent where the device cannot honour it, so the gate needed no new
     * requirement.
     *
     * The frame-rate half of that requirement is a *runtime* question, not a build-time
     * one: the same shader is fast on one device and not on another, and the spec frames
     * the capability per device. Whether a curl holds the display's refresh rate is
     * therefore measured where it runs, not asserted here.
     */
    private val canCurl: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
) : ViewModel() {

    /** The shelf this publication's reading mode is remembered under. */
    private val shelf =
        ShelfMemory.shelf(publication.series, publication.identity.stableId)

    /**
     * What to call the shelf when telling the reader what a setting applies to.
     *
     * The series when there is one. A publication with none is its own shelf, and its title
     * is what a reader would call that.
     */
    val shelfName: String get() = publication.series ?: publication.displayTitle

    private val _settings = MutableStateFlow(
        shelfStore?.themes()?.theme(ThemeScope.FIXED_LAYOUT, shelf) ?: ShelfSettings(),
    )

    /** What this shelf is read with. */
    val settings: StateFlow<ShelfSettings> = _settings.asStateFlow()

    /**
     * Whether the reader has asked the system to remove animations.
     *
     * Android has no `UIAccessibility.isReduceMotionEnabled`; what it has is an
     * animator duration scale a reader can set to zero in developer options or in
     * accessibility settings. Read on demand rather than cached, because
     * `page-transitions` requires turning the setting off mid-session to restore the
     * chosen mode "without the reader being reopened".
     */
    private val reduceMotion: Boolean
        get() = Settings.Global.getFloat(
            resolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f

    /**
     * Which transition rows to offer, which of them cannot run, and what runs instead.
     *
     * Recomputed rather than stored, because two of its three inputs are conditions of
     * the moment: the reduced-motion setting can be turned off, and the next device may
     * be able to curl. `page-transitions` requires a stored Curl to survive both.
     */
    fun transitions(settings: ShelfSettings): TransitionChoices = TransitionChoices(
        chosen = settings.transition,
        axis = settings.scrollAxis ?: impliedAxis,
        reduceMotion = reduceMotion,
        canCurl = canCurl,
    )

    /**
     * The axis the publication implies, until the reader overrides it.
     *
     * Measured from the first page that has been decoded rather than declared: a
     * webtoon rarely says it is one, and `comic-reader` recognises it by pages
     * "materially taller than they are wide".
     */
    private val impliedAxis: ScrollAxis
        get() = ScrollAxis.implied(
            isReflowable = false,
            isTall = tallestRatio >= ScrollAxis.TALLNESS_THRESHOLD,
            declaresHorizontal = true,
        )

    /** Height over width of the first decoded page, or 0 while nothing is decoded. */
    private var tallestRatio = 0.0

    /**
     * The colour behind the page, and only behind it.
     *
     * `reading-themes`: a custom background "applies to the area around the page and not to
     * the page itself, because tinting artwork is not a reading preference". So this is the
     * matte, the artwork is drawn over it untouched, and a *preset* does not reach here at
     * all — a preset is a typographic theme and its paper colour means nothing to a page of
     * artwork. Only a colour the reader chose explicitly applies.
     *
     * Black otherwise, which is what a comic is read against.
     */
    val matte: String?
        get() = _settings.value.theme.custom?.background

    /** Chooses a transition, for this shelf, from now on. */
    fun choose(transition: PageTransition) {
        update(_settings.value.copy(transition = transition))
    }

    /** Overrides the scroll axis, which `page-transitions` requires to be possible. */
    fun choose(axis: ScrollAxis) {
        update(_settings.value.copy(scrollAxis = axis, transition = scrollAlong(axis)))
    }

    /**
     * Changes what is done to a page before it is shown, for this shelf.
     *
     * `comic-reader` requires an adjustment to apply "to the series and [not be] applied
     * globally", and the shelf is exactly that.
     */
    fun choose(adjustments: ImageAdjustments) {
        update(_settings.value.copy(adjustments = adjustments.clamped()))
    }

    private fun update(settings: ShelfSettings) {
        _settings.value = settings
        val store = shelfStore ?: return
        store.save(store.themes().remembering(settings, ThemeScope.FIXED_LAYOUT, shelf))
    }

    private val _pages = MutableStateFlow<List<PageEntry>>(emptyList())
    val pages: StateFlow<List<PageEntry>> = _pages.asStateFlow()

    private val _failure = MutableStateFlow<String?>(null)
    val failure: StateFlow<String?> = _failure.asStateFlow()

    private val _isOpened = MutableStateFlow(false)

    /**
     * Whether opening has finished, however it went.
     *
     * An archive with no decodable images is not a failure the opener reports: it opens
     * cleanly and yields an empty page list. Without knowing that opening had *finished*,
     * the screen could not tell "still loading" from "nothing to show", and sat on its
     * spinner for ever -- which is what a fixed-layout EPUB holding no images did. iOS's
     * `noteIfEmpty` answers the same question inside the model.
     */
    val isOpened: StateFlow<Boolean> = _isOpened.asStateFlow()

    /**
     * How many pages to keep decoded, and in which direction.
     *
     * `comic-reader`: "at least the next three and previous one page are decoded
     * and held ready". Asymmetric because reading is: three ahead covers a fast run
     * of turns, one behind covers the glance back, and five pages of a 2000x3000
     * corpus is a bound `publication-formats` is happy with.
     */
    private val lookAhead = 3
    private val lookBehind = 1

    /**
     * Decoded pages, in a state map rather than a plain one.
     *
     * Compose does not observe a `mutableMapOf`, so filling it recomposes nothing
     * and every page sits on its spinner for ever. iOS gets this from `@Observable`
     * tracking the property; Kotlin has to say it.
     */
    private val decoded = mutableStateMapOf<Int, Bitmap>()

    /**
     * Small versions of pages, for the thumbnail strip.
     *
     * Kept apart from [decoded] because the two have different lifetimes: a page
     * leaves the reading window as soon as it is three turns away, and a thumbnail
     * is wanted for as long as the strip is open.
     */
    private val thumbnails = mutableStateMapOf<Int, Bitmap>()
    private val attempted = mutableStateSetOf<Int>()
    private var archive: ComicArchiveReading? = null

    /**
     * Set instead of [archive] for a PDF, whose pages are drawn rather than
     * stored. `ebook-reader` requires a several-hundred-megabyte PDF to render
     * pages as they are needed, so nothing is rasterised until it is asked for.
     */
    private var pdf: PdfDocumentReader? = null

    /**
     * `PdfRenderer` permits one open page at a time and says so. Warming a window
     * of three pages would otherwise render them concurrently and throw.
     */
    private val pdfLock = Mutex()

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
        if (publication.format == PublicationFormat.PDF) {
            openPdf()
            return
        }
        try {
            val opened = withContext(Dispatchers.IO) {
                PublicationAccess.openArchive(resolver, path)
            }
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
        _isOpened.value = true
    }

    /**
     * Opens a PDF.
     *
     * Its own path because a PDF has no entries to list: the page list is the page
     * *count*, and each entry exists only to give the pager something to count and
     * to label. A recorded position still wins over page one.
     */
    private suspend fun openPdf() {
        try {
            val reader = withContext(Dispatchers.IO) {
                PublicationAccess.openPdf(resolver, path)
            }
            pdf = reader
            _pages.value = (0 until reader.pageCount).map { PageEntry("${'$'}{it + 1}", 0L) }
            val recorded = progress?.progress(publication.identity)?.position
            if (recorded is ReadingPosition.Page && recorded.index in _pages.value.indices) {
                initialIndex = recorded.index
            }
        } catch (cause: Exception) {
            _failure.value = cause.message ?: "could not be opened"
        }
        _isOpened.value = true
    }

    fun image(index: Int): Bitmap? = decoded[index]

    /**
     * A small version of a page, decoded on demand.
     *
     * `comic-reader`: the thumbnail browser shows "every page ... in a scrollable
     * strip". Every page, so the strip is lazy and this is called per cell as it
     * scrolls into view rather than for the whole publication at once — a 300-page
     * comic would otherwise read 300 archive entries to open a strip.
     */
    suspend fun thumbnail(index: Int): Bitmap? {
        thumbnails[index]?.let { return it }
        val opened = archive ?: return null
        val page = _pages.value.getOrNull(index) ?: return null

        val bitmap = withContext(Dispatchers.IO) {
            runCatching { PageDecoder.decode(opened.data(page), THUMBNAIL_PIXEL_SIZE) }.getOrNull()
        } ?: return null

        evictDistantThumbnails(index)
        thumbnails[index] = bitmap
        return bitmap
    }

    /**
     * Drops the thumbnails furthest from where the reader is looking, because the
     * strip scrolls outward from the current page in both directions.
     */
    private fun evictDistantThumbnails(index: Int) {
        if (thumbnails.size < THUMBNAIL_BUDGET) return
        thumbnails.keys
            .sortedByDescending { kotlin.math.abs(it - index) }
            .take(thumbnails.size - THUMBNAIL_BUDGET + 1)
            .forEach { thumbnails.remove(it) }
    }

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
        val wanted = ((index - lookBehind)..(index + lookAhead))
            .filter { it in pages.indices }
            .toSet()
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
        val reader = pdf
        val bitmap = if (reader != null) {
            withContext(Dispatchers.IO) {
                pdfLock.withLock {
                    runCatching { reader.render(index, maxPixelSize) }.getOrNull()
                }
            }
        } else {
            val opened = archive ?: return
            withContext(Dispatchers.IO) {
                runCatching { PageDecoder.decode(opened.data(page), maxPixelSize) }.getOrNull()
            }
        }
        if (bitmap == null) {
            // Forgotten rather than remembered as tried. A page that failed because the
            // share was away must be readable once it comes back -- `network-share` asks
            // the app to "resume streaming at the current page" after reconnecting, and a
            // page marked attempted for ever never gets a second chance.
            attempted.remove(index)
        }
        if (bitmap != null) {
            decoded[index] = bitmap
            // The first page that decodes settles the implied scroll axis. First
            // rather than tallest: a webtoon's pages are all strips, and waiting for
            // the tallest would mean waiting for the whole publication.
            if (tallestRatio == 0.0 && bitmap.width > 0) {
                tallestRatio = bitmap.height.toDouble() / bitmap.width
            }
        }
    }

    private companion object {
        /** Enough to recognise a page by its composition, not to read it. */
        const val THUMBNAIL_PIXEL_SIZE = 160

        /**
         * How many thumbnails to keep. A 300-page comic's worth would be tens of
         * megabytes of pixels for a strip showing eight of them at a time.
         */
        const val THUMBNAIL_BUDGET = 64
    }

    override fun onCleared() {
        archive?.close()
        pdf?.close()
        decoded.clear()
        thumbnails.clear()
    }
}
