package app.storyarc.feature.reader

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateSetOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.feedback.StoryArcFeedback
import app.storyarc.core.designsystem.feedback.rememberHaptics
import app.storyarc.core.designsystem.navigation.StoryArcSupportingPanes
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.core.designsystem.theme.LocalTapTurnsPages
import app.storyarc.core.designsystem.theme.LocalVolumeTurns
import app.storyarc.core.format.PageEntry
import app.storyarc.core.format.PdfTextPoint
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageReturn
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.SearchMatch
import app.storyarc.core.model.SpreadLayout
import app.storyarc.core.model.pairsPages
import app.storyarc.core.model.scrollAxis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun Pager(
    viewModel: ReaderViewModel,
    pages: List<PageEntry>,
    onClose: () -> Unit,
    previousInSeries: Publication?,
    nextInSeries: Publication?,
    onOpen: (Publication) -> Unit,
    downloadCleanup: DownloadCleanupOffer?,
    fit: PageFit,
    onFitChange: (PageFit) -> Unit,
    /** What shows behind and beside the page. See [matteColour]. */
    matte: Color,
) {
    val count = pages.size
    val skipped by viewModel.skippedPageCount.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val adjustments = settings.adjustments
    val direction = viewModel.readingDirection(settings)
    val isRightToLeft = direction == ReadingDirection.RIGHT_TO_LEFT
    val reduceMotion by viewModel.reduceMotionFlow.collectAsStateWithLifecycle()
    val choices = viewModel.transitions(settings, reduceMotion)

    /**
     * Whether two pages can share the screen.
     *
     * `comic-reader` scopes the pairing to landscape itself. Which modes pair is
     * [pairsPages], so the two platforms answer it once. Curl is in since D14 -- the slot's
     * two pages are composited into one texture before the shader sees them ([SpreadTexture]).
     */
    val isPairing = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE &&
        choices.effective.pairsPages

    /**
     * How the pages are grouped on screen: one slot per screenful, and a slot may hold
     * two pages. `wideIndices` only ever grows, so its size is enough to notice a change
     * without hashing the set itself.
     */
    val layout = remember(isPairing, count, viewModel.wideIndices.size, settings.offsetsSpreads) {
        if (isPairing) {
            SpreadLayout.paired(count, viewModel.wideIndices.toSet(), settings.offsetsSpreads)
        } else {
            SpreadLayout.single(count)
        }
    }
    val slotCount = layout.count

    /**
     * One slot past the last page in reading order, for Slide and Scroll to reach on a
     * swipe or a scroll with nothing left to turn to. See [endSlotPosition].
     */
    val endSlot = endSlotPosition(slotCount, isRightToLeft)

    /**
     * The slot a display position holds.
     *
     * Right-to-left reverses the *display* order and maps the index here, so the model
     * keeps counting pages the way the publication does and the indicator says "2 of 4"
     * rather than "3 of 4" for the same page. Mirroring the pager with a transform
     * instead would fight the paging gesture — iOS learned that the hard way, and the
     * note is in ReaderView.swift.
     */
    fun slotIndex(display: Int) = if (isRightToLeft) slotCount - 1 - display else display

    /**
     * A display position turned back into the publication's own page number: the first
     * page of the slot in reading order, which is what the counter, the slider and
     * `reading-progress` all mean.
     */
    fun modelIndex(display: Int) = layout.slotAt(slotIndex(display))?.leading ?: 0

    fun displayIndex(model: Int): Int {
        val slot = layout.slotContaining(model)
        return if (isRightToLeft) slotCount - 1 - slot else slot
    }

    // `page-transitions`: the mode "applies to the current publication immediately
    // without losing the reading position". Hoisted above the coordinator so a mode
    // change seeds the new container from where the reader already is.
    var position by remember { mutableIntStateOf(displayIndex(viewModel.initialIndex)) }

    // `native-experience`: what the cover brings to this publication's own screens.
    // Null until the cover has been read, and for a cover that carries no colour.
    val coverColours by viewModel.coverColours.collectAsStateWithLifecycle()

    /**
     * The page being read, kept apart from [position] because the two mean different
     * things when the pages regroup: turning the device changes which slot a page is in,
     * and a reader who rotates their phone should still be looking at what they were.
     */
    var readingPage by remember { mutableIntStateOf(viewModel.initialIndex) }

    /** Whether the adjustment controls are open. */
    var isAdjusting by rememberSaveable { mutableStateOf(false) }

    // The text layer of a PDF that has one, and nothing at all otherwise. Null is the whole of
    // the degradation `ebook-reader` asks for: every control below is written against it being
    // present, so a comic and a scan get no control rather than a disabled one.
    val pdfText by viewModel.pdfText.collectAsStateWithLifecycle()
    val pdfSelection by
        (pdfText?.selection ?: remember { MutableStateFlow(null) }).collectAsStateWithLifecycle()
    val pdfMarks by
        (pdfText?.marks ?: remember { MutableStateFlow(emptyMap<Int, List<PdfPageMark>>()) })
            .collectAsStateWithLifecycle()
    val pdfMatches by
        (pdfText?.matches ?: remember { MutableStateFlow(emptyList<SearchMatch>()) })
            .collectAsStateWithLifecycle()
    val pdfAnnotations by
        (pdfText?.annotations ?: remember { MutableStateFlow(emptyList<Annotation>()) })
            .collectAsStateWithLifecycle()
    val isPdfSearching by
        (pdfText?.isSearching ?: remember { MutableStateFlow(false) }).collectAsStateWithLifecycle()
    val isPdfCapped by
        (pdfText?.isCapped ?: remember { MutableStateFlow(false) }).collectAsStateWithLifecycle()

    /** Whether the find sheet -- search and marks -- is open. */
    val findingText = rememberSaveable { mutableStateOf(false) }
    var isFindingText by findingText

    /**
     * Which of the find sheet's two panels it opens on.
     *
     * The menu has a row for bookmarks and a row for search, and `comic-reader` requires
     * every control to be "reachable from here in one action". One sheet with a segmented
     * control at the top is two actions unless the row says which panel it wants.
     */
    val pdfTextTabState = rememberSaveable { mutableStateOf(PdfTextTab.SEARCH) }
    var pdfTextTab by pdfTextTabState

    /** The mark a note is being written on, or nothing. */
    val notingState = remember { mutableStateOf<Annotation?>(null) }

    /**
     * Whether the reader has been told, in one sentence, that this PDF has no text.
     *
     * Said only when they try. `ebook-reader` forbids a control that promises what it cannot do,
     * so there is no search box to explain; what is left is the press that would have selected a
     * word, and an answer to it.
     */
    val noTextState = remember { mutableStateOf(false) }
    var saysThereIsNoText by noTextState

    /**
     * What a mark's chapter is called for a PDF.
     *
     * A PDF's outline is a list of destinations, not a division of the text, so there is no
     * chapter a locator falls "inside". The page is what a reader would name, and it is what the
     * export groups under. iOS names it the same way.
     */
    val resources = LocalContext.current.resources
    val pageLabel: (Int) -> String = { resources.getString(R.string.reader_pdf_page, it + 1) }

    // D8: a comic's or a scan's page bookmarks -- the same store, and the same "Page N"
    // labelling, that a PDF's own marks use.
    val comicBookmarks = rememberComicBookmarks(viewModel.annotationStore, viewModel.publication.id)

    // `comic-reader`: "the user can disable it for a page that crops wrongly". Detection on
    // a scan is a guess, and a guess needs a way to be overruled. Held for the session
    // rather than stored: an exemption is about one page of one book in front of the reader
    // now, and a store of page numbers outlives the pages it describes.
    val uncropped = remember { mutableStateSetOf<Int>() }

    // Held for the session too, and for the same kind of reason: `comic-reader` scopes
    // the lock to "the reader only" and asks nothing about it surviving the book being
    // closed, and a reader who put the phone down flat is answering about now.
    var isOrientationLocked by rememberSaveable { mutableStateOf(false) }

    OrientationLockEffect(isOrientationLocked)

    val paging = rememberPaging(choices.effective, slotCount, position, isRightToLeft)
    LaunchedEffect(paging) {
        snapshotFlow { paging.current }.collect { position = it }
    }

    // The page the publication opens on — a ComicInfo cover, or a position
    // `reading-progress` recorded — is not known at first composition, because
    // `open()` has not run yet. So the container is seeded at zero and jumped once,
    // when the real answer arrives. Seeding alone was enough while a pager was the
    // only container, because `rememberPagerState` is restored from its own saved
    // state; a fade and a scroll have nothing saved to be restored from.
    var hasOpened by remember { mutableStateOf(false) }
    LaunchedEffect(count, viewModel.initialIndex) {
        if (hasOpened || count == 0) return@LaunchedEffect
        hasOpened = true
        val target = displayIndex(viewModel.initialIndex)
        paging.goTo(target, animate = false)
        restoreScrollFraction(paging, target, viewModel.initialIndex, viewModel)
    }
    // `comic-reader`: the scroll position is "preserved exactly" across a reopen. See
    // `ScrollProgress` for why only Scroll has a sub-page position to lose or restore.
    LaunchedEffect(paging) {
        observeScrollFraction(paging) { display, fraction ->
            if (display in 0 until slotCount) viewModel.saveScrollFraction(fraction, modelIndex(display))
        }
    }

    // `comic-reader`: a direction change "applies immediately without losing the current
    // page". The run the container lays out reverses under the reader, so the position
    // holding the page they are on moves to the other end of it. The page is read back
    // through the *previous* direction, because the position still means what it meant
    // before the choice — without that, turning a manga around would leave the reader
    // the same distance from the other cover.
    var previousDirection by remember { mutableStateOf(direction) }
    LaunchedEffect(direction) {
        if (direction == previousDirection) return@LaunchedEffect
        val page = previousDirection.position(paging.current, count)
        previousDirection = direction
        paging.goTo(direction.position(page, count), animate = false)
    }

    // The pages regroup when the device turns, when a wide page decodes, or when the
    // reader shifts the pairing. The reader keeps its *page* across that.
    LaunchedEffect(layout) {
        if (!hasOpened) return@LaunchedEffect
        paging.goTo(displayIndex(readingPage), animate = false)
    }
    val scope = rememberCoroutineScope()

    // `comic-reader`: nothing is on screen while reading, and the chrome fades out
    // again after four seconds of no interaction.
    var isChromeVisible by remember { mutableStateOf(true) }

    // `page-transitions` makes the turn zones a setting, on by default. Read here rather
    // than passed in: the reader is a feature module and the setting lives at the app
    // layer, which is the arrangement `LocalVolumeTurns` already uses for the same reason.
    val tapTurnsPages = LocalTapTurnsPages.current

    // And the system's bars go with them, so "nothing is on screen while reading" is true
    // of the clock too. One state drives both — see `SystemBarsFollowChrome`, which also
    // hands the window back when the reader leaves.
    SystemBarsFollowChrome(isChromeVisible)

    /**
     * Whether a menu is open over the chrome.
     *
     * The auto-hide has to wait for it. Opening the fit menu and reading the four
     * options takes longer than four seconds, and the chrome vanishing underneath
     * takes the menu with it — the tap that follows lands on the page and turns it.
     */
    var isMenuOpen by remember { mutableStateOf(false) }

    /**
     * Whether the reader's menu is open.
     *
     * The other half of the two-control chrome: one button leaves the publication and this
     * one is everything else. `rememberSaveable`, because a rotation while the menu is open
     * should not close it — the reader may have turned the device *to see* what a choice did.
     */
    var isReaderMenuOpen by rememberSaveable { mutableStateOf(false) }

    /** Set when the reader turns past the last page. */
    var hasReachedEnd by remember { mutableStateOf(false) }

    /** D6: the pinch, as a multiple of the fit, to carry on while `fit` is fit-to-width. */
    val carriedZoom = remember { mutableStateOf<Float?>(null) }

    // `native-experience`: haptics, for the two events that have nothing else to
    // announce them. Not for a page turn — a comic read at speed is two hundred of
    // those, and a buzz on each is a defect.
    val haptics = rememberHaptics()
    val resistance = rememberRefusalResistance()

    /** Whether the browser of every page is open. */
    var isBrowsingThumbnails by remember { mutableStateOf(false) }

    /**
     * Whether that browser is a pane beside the page rather than a strip over it.
     *
     * The window's own answer, at Material's expanded boundary: below it there is only room
     * for one thing at a time, and covering the foot of the artwork is the honest way to
     * show a second; at and above it the artwork keeps the room it had and the pages sit
     * next to it.
     */
    val usesThumbnailPane = rememberWindowClass().showsTwoPanes

    /**
     * Where a jump came from, so `comic-reader`'s "control to return to the previous
     * position" has somewhere to return to.
     */
    var pageReturn by remember { mutableStateOf(PageReturn()) }

    /**
     * The page the slider is scrubbing towards, while the drag is in progress.
     *
     * `comic-reader`: "a thumbnail of the target page follows the drag ... releasing
     * jumps there". So the drag moves this and nothing else, and only the release moves
     * the reader — a slider that turned every page it passed over would decode a hundred
     * pages on the way across a comic. In the publication's own numbering, like the
     * slider it drives.
     */
    var scrubbing by remember { mutableStateOf<Int?>(null) }
    ChromeAutoHideEffect(isChromeVisible, position, isMenuOpen, isBrowsingThumbnails, isAdjusting, scrubbing) {
        isChromeVisible = false
    }

    MemoryPressureEffect(viewModel, scope) { readingPage }

    // The pager owns its position and the model follows, in one direction only.
    LaunchedEffect(position) {
        // `comic-reader`: "a swipe or a scroll past the last page reaches the end
        // screen". Slide and Scroll each carry one extra slot after the last page
        // (`endSlot`) for exactly this — reaching it is not a page to load.
        if (position == endSlot) {
            if (!hasReachedEnd) haptics.play(StoryArcFeedback.COMPLETION)
            hasReachedEnd = true
            return@LaunchedEffect
        }
        readingPage = modelIndex(position)
        // Reading back to where a jump started retires the offer to go there.
        pageReturn = pageReturn.moved(readingPage)
        viewModel.warm(readingPage)
    }

    /**
     * What a tap means, by where it landed.
     *
     * The edges turn pages and do not reveal the chrome; the centre toggles it.
     * The zones are mirrored for right-to-left for free — the pager's *data* is
     * reversed, so one step right on screen is one step right on screen whichever
     * way the story runs.
     */
    fun reachEnd() {
        if (!hasReachedEnd) haptics.play(StoryArcFeedback.COMPLETION)
        hasReachedEnd = true
    }

    fun turn(target: Int) {
        // Read now, not captured. A tap handler is created while a composition is
        // still settling, and one built when the page list was empty would carry a
        // count of zero for ever — every turn silently out of range, which looks
        // exactly like taps that do nothing.
        val slots = layout.count
        if (target in 0 until slots) {
            scope.launch { paging.goTo(target) }
            return
        }
        // `comic-reader`: turning past the last page reaches an end screen rather than
        // nothing. Asked in *slots*: in right-to-left the last slot is the first display
        // position, and in a landscape spread the last slot holds two pages, so "the
        // reader is on page count - 1" is false at exactly the moment the end is due.
        if (slotIndex(paging.current) == slotCount - 1) {
            // D10: in Curl the end screen is the next sheet, so the curl lifts the page off it.
            if (paging is Paging.Curled && curlEndsAhead(paging.current, target, isRightToLeft)) {
                scope.launch { paging.rollOffTheEnd(::reachEnd) }
            } else reachEnd()
        } else {
            // The one page turn that earns a haptic is the one that does not happen.
            // Nothing on screen says the reader is already at the first page — the page
            // simply stays put, which is indistinguishable from a missed tap.
            haptics.play(StoryArcFeedback.REFUSAL)
            val response = RefusalResponse.of(reduceMotion, isRightToLeft, paging is Paging.Scrolled)
            scope.launch { resistance.play(response) }
        }
    }

    /**
     * Moves the reader to a page it did not reach by turning.
     *
     * Separate from [turn] because a jump is the thing `comic-reader` offers a way back
     * from: "releasing jumps there, with a control to return to the previous position".
     * Turning a page is not. In the publication's own numbering, because that is what
     * the slider and the strip both count in.
     */
    fun jump(page: Int) {
        if (page !in pages.indices) return
        pageReturn = pageReturn.jumped(modelIndex(position), page)
        scope.launch { paging.goTo(displayIndex(page), animate = false) }
    }

    /** The marks and the live selection on one page, or nothing to draw. */
    fun pdfDecoration(index: Int) = pdfDecorationOn(index, pdfText != null, pdfMarks, pdfSelection)

    /**
     * How a press-and-drag on one page is answered, or null where there is nothing to select.
     *
     * A PDF with no text still answers, once: the press is what a reader does when they expect
     * to select, and silence there reads as a broken gesture rather than as a scan. A comic
     * answers nothing at all, because a comic never promised words.
     */
    fun pdfSelectionHandler(index: Int): ((PdfTextPoint, PdfTextPoint, Boolean) -> Unit)? {
        val text = pdfText
        if (text != null) {
            return { from, to, _ -> scope.launch { text.select(index, from, to) } }
        }
        if (!viewModel.isPdf) return null
        return { _, _, isFinished -> if (isFinished) saysThereIsNoText = true }
    }

    /** Goes back to where the reader was before the last jump. */
    fun returnFromJump() {
        val mark = pageReturn.mark ?: return
        pageReturn = pageReturn.taken()
        scope.launch { paging.goTo(displayIndex(mark), animate = false) }
    }

    fun handleTap(point: Offset, size: IntSize) {
        val edge = size.width * EDGE_ZONE_FRACTION
        val target = when {
            // `page-transitions`: with the zones off "a tap anywhere toggles the chrome,
            // and no tap turns a page". Not "no tap does anything" -- the way back to the
            // menu is the one thing a reader still needs from a tap.
            !tapTurnsPages -> null
            point.x < edge -> paging.current - 1
            point.x > size.width - edge -> paging.current + 1
            else -> null
        }
        if (target == null) {
            isChromeVisible = !isChromeVisible
            return
        }
        turn(target)
    }

    // Turns by `step` in reading order — "the next page to read" — rather than in the
    // display order `turn` takes its target in. Space, Page Up/Down and the volume keys
    // are non-spatial this way, unlike the arrow keys and the edge taps, which stay
    // spatial on purpose (`comic-reader`). `readingOrderStep` is what flips the sign
    // under right-to-left, where the display order is reversed (`slotIndex`).
    fun turnInReadingOrder(step: Int) {
        turn(paging.current + readingOrderStep(step, isRightToLeft))
    }

    // `page-transitions`: the volume buttons turn pages "where enabled in settings". A
    // volume key never reaches Compose — it arrives at the activity, and only the activity
    // can consume it before the system changes the volume — so the reader offers a handler
    // and the host decides whether to call it. Volume-down is documented as always "next"
    // (`MainActivity.onKeyDown`), so this is a reading-order turn, not a display-order one.
    val volume = LocalVolumeTurns.current
    DisposableEffect(volume, isRightToLeft) {
        volume.turn = { forward ->
            turnInReadingOrder(if (forward) 1 else -1)
            true
        }
        onDispose { volume.turn = null }
    }

    // `comic-reader`: the mapped keys turn pages. Arrow, page and space, plus the volume
    // buttons where the reader asked for them.
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    val keyboard = Modifier
        .fillMaxSize()
        .focusRequester(focus)
        .focusable()
        .pageTurnSemantics(readingPage + 1, pages.size, { turnInReadingOrder(1) }, { turnInReadingOrder(-1) })
        .onKeyEvent { event ->
            if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
            when (ReaderKeyAction.of(event.key)) {
                ReaderKeyAction.TurnBackward -> turn(paging.current - 1)
                ReaderKeyAction.TurnForward -> turn(paging.current + 1)
                ReaderKeyAction.PreviousInOrder -> turnInReadingOrder(-1)
                ReaderKeyAction.NextInOrder -> turnInReadingOrder(1)
                ReaderKeyAction.ToggleChrome -> isChromeVisible = !isChromeVisible
                null -> return@onKeyEvent false
            }
            true
        }

    /** The end screen: over the reader once it is reached, and under the last page as a curl lifts it (D10). */
    @Composable
    fun EndScreen() = EndOfPublication(
        title = viewModel.publication.displayTitle,
        colours = coverColours,
        next = nextInSeries,
        onOpenNext = onOpen,
        onBack = {
            hasReachedEnd = false
            // Slide and Scroll actually moved into `endSlot` to get here; Curl,
            // a tap or a key did not, because `turn` refuses before advancing
            // past the last page. Snap back to the last page underneath,
            // invisibly, so returning finds the reader where they left off.
            if (paging.current == endSlot) {
                scope.launch { paging.goTo(displayIndex(pages.lastIndex), animate = false) }
            }
        },
        onClose = onClose,
        downloadCleanup = downloadCleanup,
    )

    /** The page itself, and whatever container the transition asks for. See [ReaderPageSurface]. */
    @Composable
    fun PageSurface() = ReaderPageSurface(
        viewModel = viewModel,
        pages = pages,
        paging = paging,
        layout = layout,
        slotCount = slotCount,
        endSlot = endSlot,
        isRightToLeft = isRightToLeft,
        matte = matte,
        adjustments = adjustments,
        uncropped = uncropped,
        fit = fit,
        carriedZoom = carriedZoom,
        pdfText = pdfText,
        choices = choices,
        settings = settings,
        resistance = resistance,
        keyboard = keyboard,
        isChromeVisible = isChromeVisible,
        hasReachedEnd = hasReachedEnd,
        pageReturn = pageReturn,
        scope = scope,
        slotIndex = ::slotIndex,
        modelIndex = ::modelIndex,
        handleTap = ::handleTap,
        turn = ::turn,
        reachEnd = ::reachEnd,
        returnFromJump = ::returnFromJump,
        pdfDecoration = ::pdfDecoration,
        pdfSelectionHandler = ::pdfSelectionHandler,
        onClose = onClose,
        onOpenMenu = { isReaderMenuOpen = true },
        endScreen = { EndScreen() },
    )

    if (usesThumbnailPane) {
        // `comic-reader` asks for a browser of every page; a window this wide can put it
        // *beside* the artwork rather than over it, which is what a supporting pane is for —
        // a second view of the same publication, not a second place. Below this width the
        // strip stays where it was, over the foot of the page.
        StoryArcSupportingPanes(
            showsSupporting = isBrowsingThumbnails,
            mainPane = { PageSurface() },
            supportingPane = {
                ThumbnailColumn(
                    viewModel = viewModel,
                    pageCount = count,
                    currentIndex = modelIndex(paging.current),
                    // The same jump the strip and the slider make, so the way back from a
                    // mis-tap in a three-hundred-page comic is the one control.
                    onSelect = ::jump,
                    // The page may go under the status bar because the artwork is the
                    // point; a list of numbered cells has no such claim.
                    modifier = Modifier.safeDrawingPadding(),
                )
            },
        )
    } else {
        PageSurface()
    }

    if (isReaderMenuOpen) {
        ReaderMenuSheet(
            viewModel = viewModel,
            facts = ReaderMenuFacts(
                pageIndex = modelIndex(paging.current),
                pageCount = count,
                skippedPageCount = skipped,
                choices = choices,
                showsSeparator = settings.showsPageSeparator,
                fit = fit,
                direction = direction,
                hasPairs = layout.hasPairs,
                isOffset = settings.offsetsSpreads,
                isOrientationLocked = isOrientationLocked,
                hasPdfText = pdfText != null,
                // Only where there is no pane to hold it. On a wide window the same pages are
                // already beside the artwork, and drawing both would be the browser twice.
                showsThumbnailStrip = isBrowsingThumbnails && !usesThumbnailPane,
                previousInSeries = previousInSeries,
                nextInSeries = nextInSeries,
            ),
            actions = ReaderMenuActions(
                onDismiss = { isReaderMenuOpen = false },
                onOpenThumbnails = {
                    isBrowsingThumbnails = !isBrowsingThumbnails
                    // The pane is beside the page, so the menu has to get out of the way to
                    // let the reader see it. The strip is inside the menu and does not.
                    if (usesThumbnailPane) isReaderMenuOpen = false
                },
                onOpenText = { tab ->
                    pdfTextTab = tab
                    isReaderMenuOpen = false
                    isFindingText = true
                },
                onAdjust = {
                    isReaderMenuOpen = false
                    isAdjusting = true
                },
                // A scroll row is an axis choice: recording it as one is what makes the
                // override stick, rather than leaving the axis implied and the mode
                // disagreeing with it.
                onChooseTransition = { mode ->
                    val axis = mode.scrollAxis
                    if (axis != null) viewModel.choose(axis) else viewModel.choose(mode)
                },
                onToggleSeparator = viewModel::choosePageSeparator,
                onChooseFit = onFitChange,
                onChooseDirection = viewModel::choose,
                onToggleOffset = viewModel::chooseSpreadOffset,
                onToggleOrientation = { isOrientationLocked = it },
                onScrub = { scrubbing = it },
                onJump = { index ->
                    jump(index)
                    // `comic-reader`: "releasing jumps there and dismisses the menu". The menu
                    // leaving is what makes the jump land on the page the reader was aiming at
                    // rather than behind a bottom sheet.
                    isReaderMenuOpen = false
                },
                onOpenPublication = { publication ->
                    isReaderMenuOpen = false
                    onOpen(publication)
                },
                onBookmarkThisPage = {
                    comicBookmarks.add(modelIndex(paging.current), count, pageLabel)
                },
            ),
            scrubbing = scrubbing,
        )
    }

    if (hasReachedEnd) {
        EndScreen()
        return
    }

    // Outside the chrome, not inside it: the chrome fades and takes its children with it,
    // and a sheet that vanishes four seconds after it opens is not a sheet.
    if (isAdjusting) {
        AdjustmentsSheet(
            adjustments = adjustments,
            shelf = viewModel.shelfName,
            cropsThisPage = modelIndex(position) !in uncropped,
            onCropThisPage = { wanted ->
                val page = modelIndex(position)
                if (wanted) uncropped.remove(page) else uncropped.add(page)
            },
            onChange = viewModel::choose,
            onDismiss = { isAdjusting = false },
            matte = settings.theme.custom?.background,
            onChooseMatte = viewModel::chooseMatte,
            brightness = viewModel.brightness.collectAsStateWithLifecycle().value,
            onChooseBrightness = viewModel::chooseBrightness,
        )
    }

    // The selection menu, the find sheet, the note editor, and the one sentence a PDF with no
    // text gets. Absent for everything else, which is most of what this reader opens.
    PdfTextLayers(
        pdfText = pdfText,
        pdfSelection = pdfSelection,
        pdfMatches = pdfMatches,
        isPdfSearching = isPdfSearching,
        isPdfCapped = isPdfCapped,
        pdfAnnotations = pdfAnnotations,
        pageLabel = pageLabel,
        scope = scope,
        jump = ::jump,
        comicBookmarks = comicBookmarks,
        notingState = notingState,
        pdfTextTabState = pdfTextTabState,
        findingText = findingText,
        noTextState = noTextState,
    )
}
