package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateSet
import androidx.compose.runtime.mutableStateSetOf
import androidx.lifecycle.ViewModel
import android.content.ContentResolver
import android.os.Build
import android.provider.Settings
import app.storyarc.core.format.ComicArchiveReading
import app.storyarc.core.format.PageCodec
import app.storyarc.core.format.PageDecoder
import app.storyarc.core.format.PageEntry
import app.storyarc.core.format.PdfDocumentReader
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.CoverAccent
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.MemoryPressure
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.PrefetchWindow
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.scrollAlong
import app.storyarc.core.persistence.AnnotationStore
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
    /**
     * Where highlights and notes are kept, or null in a preview.
     *
     * The same store the reflowable reader writes to, holding the same record: a mark made in
     * a PDF and a mark made in a novel come out of one export, which is what `ebook-reader`
     * means by "listed in one place".
     */
    private val annotationStore: AnnotationStore? = null,
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

    /** Reads this shelf the other way round, from now on. */
    fun choose(direction: ReadingDirection) {
        update(_settings.value.copy(readingDirection = direction))
    }

    /**
     * Shifts the spread pairing by one, or puts it back, for this shelf from now on.
     *
     * `comic-reader` asks for the offset "for publications whose cover throws the pairing
     * off", and that is a fact about the series rather than about the reader — so it is
     * remembered where the reading mode is, and issue two opens paired right.
     */
    fun chooseSpreadOffset(isOffset: Boolean) {
        update(_settings.value.copy(offsetsSpreads = isOffset))
    }

    /** Shows or hides the line between pages in a continuous scroll. */
    fun choosePageSeparator(isShown: Boolean) {
        update(_settings.value.copy(showsPageSeparator = isShown))
    }

    /**
     * Sizes the page a different way, for this shelf from now on.
     *
     * `comic-reader` requires the fit to persist "per series". It used to be one value for
     * the whole library, so fit-to-width chosen for a manga changed how every other comic
     * opened; it is now kept where the other six per-series reader choices are.
     */
    fun chooseFit(fit: PageFit) {
        update(_settings.value.copy(fit = fit))
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

    private val _skippedPageCount = MutableStateFlow(0)

    /**
     * Entries that looked like pages and could not be read at all.
     *
     * `publication-formats`: a corrupt archive opens "whatever pages it can read and
     * states how many were skipped, rather than refusing the whole publication". The
     * archive counts them; this is where the reader can say so.
     */
    val skippedPageCount: StateFlow<Int> = _skippedPageCount.asStateFlow()

    private val _coverColours = MutableStateFlow<CoverColours?>(null)

    /** What this publication's cover brings to its own screens, or null when it brings none. */
    val coverColours: StateFlow<CoverColours?> = _coverColours.asStateFlow()

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
     * Starts at the window `comic-reader` asks for and narrows when the system asks for
     * memory back — see [noteMemoryPressure]. A `var` for that reason: the spec's floor
     * is a floor for normal conditions, not for the moment the system is choosing a
     * process to end.
     */
    private var prefetch = PrefetchWindow.FULL

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

    /**
     * The codec of each page that was attempted and refused. See [codecName].
     *
     * A snapshot map for the reason [decoded] is one: the placeholder is drawn from it,
     * and Compose does not observe a `mutableMapOf`.
     */
    private val refusedCodecs = mutableStateMapOf<Int, String>()

    /**
     * A page held at the resolution a zoom asked for.
     *
     * One page at a time, on purpose: the reader is looking at one, and a second copy of
     * a 2000x3000 scan is 24 MB that the prefetch window has already budgeted for
     * something else.
     *
     * @property pixelSize what it was decoded at, so an unchanged pinch does not decode
     *   it again.
     */
    private data class ZoomedPage(val index: Int, val pixelSize: Int, val bitmap: Bitmap)

    private var zoomed by mutableStateOf<ZoomedPage?>(null)

    /**
     * Pages that take the width of two.
     *
     * `comic-reader` shows such a page alone rather than pairing it with a neighbour. Two
     * sources, answering different halves of the same question: `ComicInfo` *declares*
     * spreads and is believed outright, and a page that decoded wider than it is tall is
     * one whether the file says so or not — most CBZs carry no metadata at all, so a
     * declaration alone would find nothing in the common case.
     *
     * A snapshot set rather than a plain one, for the reason [decoded] is: the screen
     * regroups its pages when this grows, and Compose does not observe a `mutableSetOf`.
     */
    private val wide = mutableStateSetOf<Int>()

    /**
     * Pages that take the width of two, for the screen to lay out around.
     *
     * Grows as pages decode, which means a landscape layout can regroup itself a few
     * pages ahead of the reader. That is what "detected" means; the screen keeps its
     * *page* across the regrouping rather than its slot, so nothing moves under it.
     */
    val wideIndices: Set<Int> get() = wide
    private var archive: ComicArchiveReading? = null

    /**
     * Set instead of [archive] for a PDF, whose pages are drawn rather than
     * stored. `ebook-reader` requires a several-hundred-megabyte PDF to render
     * pages as they are needed, so nothing is rasterised until it is asked for.
     */
    private var pdf: PdfDocumentReader? = null

    private val _pdfText = MutableStateFlow<PdfTextState?>(null)

    /**
     * The text layer of a PDF that has one, and nothing at all otherwise.
     *
     * Null is the whole of the degradation `ebook-reader` asks for: a comic, a PDF that is
     * images only, and a device with no PDF text API (ADR-0012) all arrive here the same way,
     * and every control that depends on text is written against this being present rather than
     * against a flag.
     */
    internal val pdfText: StateFlow<PdfTextState?> = _pdfText.asStateFlow()

    /**
     * Whether this publication is a PDF at all.
     *
     * What tells "there is no text in this file" apart from "this is a comic": only the first
     * has anything to say to a reader who presses on a word expecting to select it.
     */
    val isPdf: Boolean get() = publication.format == PublicationFormat.PDF

    /**
     * `PdfRenderer` permits one open page at a time and says so. Warming a window
     * of three pages would otherwise render them concurrently and throw.
     */
    private val pdfLock = Mutex()

    private var maxPixelSize = 2048

    /**
     * The direction the reader turns pages in.
     *
     * The publication's own — from `ComicInfo` or the language — until the reader
     * overrules it. `comic-reader` lets them, because metadata is often wrong about this
     * and a manga tagged left-to-right is unreadable; the override is "remembered for the
     * series", so it is kept where every other per-series decision is kept rather than
     * against this one file.
     *
     * Takes the settings rather than reading them, exactly as [transitions] does: the
     * screen already collects that flow, and a `.value` read inside a composition is a
     * snapshot nothing recomposes on — the reader would have to leave and come back to
     * see the pages turn the other way.
     */
    fun readingDirection(settings: ShelfSettings): ReadingDirection =
        settings.readingDirection ?: publication.readingDirection

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
            _skippedPageCount.value = opened.skippedPageCount
            wide.addAll(opened.doublePageIndices)
            publication.coverPath?.let { path ->
                val index = opened.pages.indexOfFirst { it.path == path }
                if (index >= 0) initialIndex = index
            }
            // A recorded position wins over the cover. `reading-progress` is about
            // picking up where you left off, and a book you are halfway through
            // should not reopen at its cover.
            //
            // Unless it is finished, which the same requirement singles out: reopening a
            // finished publication "starts at the beginning while retaining the finished
            // record". Dropping the override is the whole of it — the record is untouched,
            // and the beginning is where `initialIndex` already is.
            val record = progress?.progress(publication.identity)
            val recorded = record?.position?.takeUnless { record.isFinished }
            if (recorded is ReadingPosition.Page && recorded.index in opened.pages.indices) {
                initialIndex = recorded.index
            }
            deriveCoverColours()
        } catch (cause: Exception) {
            _failure.value = cause.message ?: "could not be opened"
        }
        _isOpened.value = true
    }

    /**
     * Derives the cover's colours, once, when the publication opens.
     *
     * `native-experience`: "accent and background tinting derive from the publication's
     * cover art". From the *cover* rather than from the page in front of the reader,
     * because a book resumed at page 57 is still that book — and from the cover's
     * thumbnail rather than the full page, because a colour census wants a thousand
     * pixels and decoding a 2000×3000 scan to find them would be paying for a picture
     * nobody looks at.
     *
     * Quiet about a PDF, which never reaches here, and about a cover that is all ink and
     * paper. Both leave this null, and a screen with no cover colour uses the brand
     * accent — which is what `native-experience` asks for on a surface with no
     * publication colour of its own.
     */
    private suspend fun deriveCoverColours() {
        val cover = thumbnail(coverIndex()) ?: return
        _coverColours.value = withContext(Dispatchers.Default) {
            CoverAccent.derived(CoverAccent.pixels(cover))
        }
    }

    /** The designated cover when `ComicInfo` named one, page one otherwise. */
    private fun coverIndex(): Int {
        val named = publication.coverPath ?: return 0
        return _pages.value.indexOfFirst { it.path == named }.takeIf { it >= 0 } ?: 0
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
            // The same file again, for what is written on it. Absent for a scan, and absent
            // on a device whose PDF module predates the text API -- both of which the reader
            // answers by offering nothing rather than by offering something broken.
            openPdfText(reader.pageCount)
            // Finished reopens at page one, exactly as an archive does.
            val record = progress?.progress(publication.identity)
            val recorded = record?.position?.takeUnless { record.isFinished }
            if (recorded is ReadingPosition.Page && recorded.index in _pages.value.indices) {
                initialIndex = recorded.index
            }
        } catch (cause: Exception) {
            _failure.value = cause.message ?: "could not be opened"
        }
        _isOpened.value = true
    }

    /**
     * Opens the same PDF a second time, for its text.
     *
     * A second handle rather than a second use of the first: the renderer permits one open page
     * at a time, and a selection that waited behind a page render would arrive after the finger
     * had moved. Probing for a text layer opens pages, so it happens off the main thread.
     *
     * Closed again the moment it turns out to have nothing to say. A scan opens, is asked, and
     * is let go before the reader has drawn a page.
     */
    private suspend fun openPdfText(pageCount: Int) {
        val opened = withContext(Dispatchers.IO) {
            val reader = PublicationAccess.openPdfText(resolver, path) ?: return@withContext null
            if (reader.hasTextLayer) {
                reader
            } else {
                reader.close()
                null
            }
        } ?: return

        val state = PdfTextState(
            reader = opened,
            store = annotationStore,
            publication = publication.identity.stableId,
            title = publication.displayTitle,
            pageCount = pageCount,
        )
        state.load()
        _pdfText.value = state
    }

    fun image(index: Int): Bitmap? = decoded[index]

    /**
     * What to draw for a page: the copy re-decoded for a held zoom when there is one,
     * and the display-resolution copy otherwise.
     *
     * The one call a page composable should make. `publication-formats` requires a page
     * to be "downsampled to the display's needs for viewing and re-decoded at higher
     * resolution when the user zooms", and which of the two is in hand is not a
     * distinction a composable should have to carry.
     */
    fun displayImage(index: Int): Bitmap? {
        zoomed?.let { if (it.index == index) return it.bitmap }
        return decoded[index]
    }

    /**
     * What a page that would not decode turned out to be, when its bytes said.
     *
     * `publication-formats`: an undecodable page "displays a placeholder naming the
     * codec". Null when nothing could be read at all, in which case there is no codec to
     * name and the placeholder says only that the page could not be read.
     */
    fun codecName(index: Int): String? = refusedCodecs[index]

    /**
     * Re-decodes the page under a held zoom at the resolution the zoom asks for.
     *
     * `publication-formats`: a page too large for the device is "downsampled to the
     * display's needs for viewing and re-decoded at higher resolution when the user
     * zooms". Decoding to the *display* is what makes a comic readable on a phone at
     * all; it is also what makes a magnified page soft, because the pixels that would
     * have carried the lettering were thrown away before the reader asked for them.
     *
     * Held, not permanent: [releaseZoom] drops the larger copy and the page falls back
     * to the display-resolution one, which is still decoded and still in the window. So
     * the cost is one extra page for as long as a finger is on the screen.
     *
     * Nothing happens when [PrefetchWindow.zoomedPixelSize] declines — a pinch too small
     * to see, or a window narrowed by memory pressure.
     */
    suspend fun holdZoom(scale: Float, index: Int) {
        val target = prefetch.zoomedPixelSize(maxPixelSize, scale)
        if (target == null) {
            releaseZoom()
            return
        }
        val page = _pages.value.getOrNull(index) ?: return
        // Already at this size, or larger: a pinch that wanders inside one step of the
        // ceiling should not decode the page again on every settle.
        zoomed?.let { if (it.index == index && it.pixelSize >= target) return }
        val bitmap = decodeBitmap(index, page, target) ?: return
        zoomed = ZoomedPage(index, target, bitmap)
    }

    /** Drops the page held for a zoom. The display-resolution copy takes over again. */
    fun releaseZoom() {
        zoomed = null
    }

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

    /**
     * Narrows or restores the prefetch window, and drops what no longer fits.
     *
     * `comic-reader`: "prefetch depth shrinks under memory pressure rather than the app
     * being terminated". Shrinking has to take effect at once rather than at the next
     * turn — the pages already held are the ones the system is asking for back, and a
     * window that only narrowed on the way to the next page would give up nothing while
     * the reader sat still.
     *
     * Thumbnails go entirely under critical pressure: up to sixty-four small pages held
     * for a strip the reader may not have open, each re-decoded on demand.
     *
     * Unlike iOS, Android never says the pressure has lifted — `onTrimMemory` only ever
     * reports trouble. So the screen calls this with [MemoryPressure.NORMAL] when the
     * reader comes back to the foreground, which is the nearest thing to an all-clear the
     * platform offers.
     */
    suspend fun noteMemoryPressure(pressure: MemoryPressure, at: Int) {
        val window = PrefetchWindow.under(pressure)
        if (window == prefetch) return
        // A page held at three times the display's resolution is the largest single
        // thing this reader owns, so it goes first when the window narrows — before the
        // neighbours, which are the pages a turn is waiting on. The next settle of the
        // pinch asks again, against the narrower ceiling.
        if (window.zoomCeiling < prefetch.zoomCeiling) zoomed = null
        prefetch = window
        if (pressure == MemoryPressure.CRITICAL) thumbnails.clear()
        warm(at)
    }

    /** Decodes the page at [index] and its neighbours, and drops the rest. */
    suspend fun warm(index: Int) {
        record(index)
        val pages = _pages.value
        val wanted = prefetch.pages(around = index, of = pages.size)
        // Dropped before decoding, so peak memory is the window and not the window
        // plus whatever was there before.
        (decoded.keys - wanted).forEach {
            decoded.remove(it)
            attempted.remove(it)
            refusedCodecs.remove(it)
        }
        // A zoom held on a page the reader has moved away from is the same waste as a
        // decoded page outside the window, only three times the size.
        zoomed?.let { if (it.index !in wanted) zoomed = null }
        // The current page first: a turn should not wait on its neighbours.
        for (target in listOf(index) + wanted.sortedBy { kotlin.math.abs(it - index) }) {
            if (target !in pages.indices || target in attempted) continue
            attempted += target
            decode(target, pages[target])
        }
    }

    /**
     * One decode of one page, and what it settled.
     *
     * The distinction between the last two cases is the reason this exists. Both used to
     * be "no bitmap", and treating a refusal as a missing read left the reader spinning
     * for ever on a page nothing was ever going to produce.
     */
    private sealed interface PageOutcome {
        data class Decoded(val bitmap: Bitmap) : PageOutcome

        /**
         * The bytes arrived and the decoder would not have them. Permanent for this
         * file, and [codec] is what `publication-formats` wants named in the placeholder
         * — null when the bytes say nothing recognisable at all.
         */
        data class Refused(val codec: String?) : PageOutcome

        /**
         * The bytes could not be read. Usually the source is away, so it is worth asking
         * again.
         */
        data object Unread : PageOutcome
    }

    private suspend fun decode(index: Int, page: PageEntry) {
        when (val result = outcome(index, page, maxPixelSize)) {
            is PageOutcome.Decoded -> {
                val bitmap = result.bitmap
                decoded[index] = bitmap
                refusedCodecs.remove(index)
                // The first page that decodes settles the implied scroll axis. First
                // rather than tallest: a webtoon's pages are all strips, and waiting for
                // the tallest would mean waiting for the whole publication.
                if (tallestRatio == 0.0 && bitmap.width > 0) {
                    tallestRatio = bitmap.height.toDouble() / bitmap.width
                }
                // Wider than tall, with no tolerance to tune: a portrait page scanned
                // with a slight skew is still portrait, and a spread is half again as
                // wide as a page.
                if (bitmap.width > bitmap.height) wide += index
            }

            is PageOutcome.Refused ->
                // Remembered as tried, which is what makes the placeholder appear: the
                // bytes are here and the decoder will say the same thing about them next
                // time.
                result.codec?.let { refusedCodecs[index] = it }

            PageOutcome.Unread ->
                // Forgotten rather than remembered as tried. A page that failed because
                // the share was away must be readable once it comes back --
                // `network-share` asks the app to "resume streaming at the current page"
                // after reconnecting, and a page marked attempted for ever never gets a
                // second chance.
                attempted.remove(index)
        }
    }

    private suspend fun outcome(index: Int, page: PageEntry, size: Int): PageOutcome {
        val reader = pdf
        if (reader != null) {
            val rendered = withContext(Dispatchers.IO) {
                pdfLock.withLock { runCatching { reader.render(index, size) }.getOrNull() }
            }
            // A PDF page is drawn rather than stored, so there are no codec bytes to
            // sniff. The format is still what was refused, and naming it is the point:
            // `publication-formats` asks for "the codec or format".
            return rendered?.let { PageOutcome.Decoded(it) }
                ?: PageOutcome.Refused(PublicationFormat.PDF.displayName)
        }
        val opened = archive ?: return PageOutcome.Unread
        return withContext(Dispatchers.IO) {
            val data = runCatching { opened.data(page) }.getOrNull()
                ?: return@withContext PageOutcome.Unread
            runCatching { PageDecoder.decode(data, size) }.getOrNull()
                ?.let { PageOutcome.Decoded(it) }
                ?: PageOutcome.Refused(PageCodec.nameOf(data, page.path))
        }
    }

    /** The same decode, without the bookkeeping, for a zoom that wants one page larger. */
    private suspend fun decodeBitmap(index: Int, page: PageEntry, size: Int): Bitmap? =
        (outcome(index, page, size) as? PageOutcome.Decoded)?.bitmap

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
        _pdfText.value?.close()
        decoded.clear()
        thumbnails.clear()
        wide.clear()
        refusedCodecs.clear()
        zoomed = null
    }
}
