package app.storyarc.feature.reader

import android.content.ComponentCallbacks2
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.ScreenLockRotation
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.feedback.StoryArcFeedback
import app.storyarc.core.designsystem.feedback.rememberHaptics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.LocalVolumeTurns
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PageEntry
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.MemoryPressure
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageReturn
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.SpreadLayout
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.scrollAxis
import app.storyarc.core.persistence.ReaderPreferences
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The paged comic reader.
 *
 * `comic-reader` lists five transition modes. This is **slide**, the one that needs
 * no shader — page curl and continuous scroll belong to the
 * `reader-theming-and-page-transitions` change, whose Phase 0 spikes decide how the
 * curl is drawn on each platform. Building one here would pre-empt that decision.
 *
 * What is here is what every mode shares: page order, reading direction, fit, zoom,
 * and chrome that gets out of the way. Fit *modes* — fit-to-width, fit-to-height,
 * original size — are not here yet; the reader fits the whole page and zoom starts
 * from that.
 *
 * iOS's `ReaderView` is the same reader with `TabView` in place of `HorizontalPager`
 * and a `UIScrollView` in place of the transformable modifier.
 */
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onClose: () -> Unit,
    /** Where the fit choice is remembered. Absent in previews. */
    preferences: ReaderPreferences? = null,
    /**
     * What surrounds this publication in its series, and how to open one of them.
     * Supplied by the app layer: the reader does not know what a library is, and a
     * feature module never depends on another feature module.
     *
     * `comic-reader` asks for previous and next chapter actions "without returning to
     * the library", and one publication of a series is what a chapter is here — so the
     * same two neighbours answer both the chapter buttons and the end screen.
     */
    previousInSeries: Publication? = null,
    nextInSeries: Publication? = null,
    onOpen: (Publication) -> Unit = {},
    /**
     * When reads from the source started failing, if they have.
     *
     * Supplied by the app layer for the same reason as the above: the reader does not know
     * what a network share is, and `network-share`'s two thresholds are the only part of
     * that it needs.
     */
    blockedSince: Long? = null,
    onDismissTrouble: () -> Unit = {},
    onDownloadForOffline: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val pages by viewModel.pages.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()
    val isOpened by viewModel.isOpened.collectAsStateWithLifecycle()

    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val maxPixelSize = with(density) {
        maxOf(configuration.screenWidthDp.dp, configuration.screenHeightDp.dp).roundToPx()
    }

    // Keyed on the model, not on `Unit`. The end screen swaps in the next issue
    // without leaving this composable, so an effect that runs once would open the
    // first publication and then show a spinner for ever on the second.
    LaunchedEffect(viewModel) { viewModel.open(maxPixelSize) }

    // `comic-reader`: the fit choice persists. Stored globally rather than per
    // series — the spec says per series, and a series is not yet a thing the app
    // can key anything on.
    var fit by rememberSaveable { mutableStateOf(preferences?.pageFit() ?: PageFit.SCREEN) }
    LaunchedEffect(fit) { preferences?.save(fit) }

    // `comic-reader`: "the screen does not auto-lock while a page is visible, and
    // normal locking resumes on leaving". A long look at one page is reading, not
    // idling. On the view rather than the window flag, so leaving the screen
    // restores the device's own behaviour without the reader having to remember to.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    // `reading-themes`: a custom background "applies to the area around the page and not
    // to the page itself, because tinting artwork is not a reading preference". This is
    // that area, and black is what it is until a reader says otherwise.
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val matte = remember(settings) { matteColour(settings.theme.custom?.background) }

    Box(
        modifier = modifier.fillMaxSize().background(matte),
        contentAlignment = Alignment.Center,
    ) {
        when {
            failure != null -> {
                Message(failure!!)
                CloseButton(onClose)
            }
            pages.isEmpty() && isOpened -> {
                Message(stringResource(R.string.reader_empty))
                CloseButton(onClose)
            }
            pages.isEmpty() -> {
                DelayedProgressIndicator()
                CloseButton(onClose)
            }
            else -> Pager(
                viewModel = viewModel,
                pages = pages,
                onClose = onClose,
                previousInSeries = previousInSeries,
                nextInSeries = nextInSeries,
                onOpen = onOpen,
                fit = fit,
                onFitChange = { fit = it },
                matte = matte,
            )
        }

        // Over the page rather than in place of it: `network-share` requires pages already
        // read to stay readable while the network is away.
        NetworkNotice(
            blockedSince = blockedSince,
            onDismiss = onDismissTrouble,
            onDownload = onDownloadForOffline,
            onLeave = onClose,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.CloseButton(onClose: () -> Unit) {
    IconButton(
        onClick = onClose,
        modifier = Modifier.align(Alignment.TopStart).padding(StoryArcSpace.md),
    ) {
        // Scrim, not a 20% white pill: the chrome draws straight onto the page art, and
        // over a white manga page a white icon on a white pill measured 1:1.
        Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = stringResource(R.string.reader_close),
                tint = Color.White,
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

@Composable
private fun Pager(
    viewModel: ReaderViewModel,
    pages: List<PageEntry>,
    onClose: () -> Unit,
    previousInSeries: Publication?,
    nextInSeries: Publication?,
    onOpen: (Publication) -> Unit,
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

    val choices = viewModel.transitions(settings)

    /**
     * Whether two pages can share the screen.
     *
     * `comic-reader` scopes the pairing to landscape itself. Curl is out because the
     * shader takes one decoded page and compositing two into a single texture is a
     * different piece of work; a continuous scroll is out because it has no facing pages
     * to pair — it has a strip.
     */
    val isPairing = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE &&
        (choices.effective == PageTransition.SLIDE || choices.effective == PageTransition.FAST_FADE)

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

    // `comic-reader`: "the user can disable it for a page that crops wrongly". Detection on
    // a scan is a guess, and a guess needs a way to be overruled. Held for the session
    // rather than stored: an exemption is about one page of one book in front of the reader
    // now, and a store of page numbers outlives the pages it describes.
    val uncropped = remember { mutableStateSetOf<Int>() }

    // Held for the session too, and for the same kind of reason: `comic-reader` scopes
    // the lock to "the reader only" and asks nothing about it surviving the book being
    // closed, and a reader who put the phone down flat is answering about now.
    var isOrientationLocked by rememberSaveable { mutableStateOf(false) }

    // `comic-reader`: a locked orientation "stays locked for the reader only, and the
    // rest of the app follows the device". `SCREEN_ORIENTATION_LOCKED` pins the activity
    // to the way up it is already showing, whichever that is, and the effect hands it
    // back on the way out — which is what makes it the reader's lock and not the app's.
    val activity = LocalActivity.current
    DisposableEffect(activity, isOrientationLocked) {
        activity?.requestedOrientation = if (isOrientationLocked) {
            ActivityInfo.SCREEN_ORIENTATION_LOCKED
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }

    val paging = rememberPaging(choices.effective, slotCount, position)
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
        paging.goTo(displayIndex(viewModel.initialIndex), animate = false)
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

    /**
     * Whether a menu is open over the chrome.
     *
     * The auto-hide has to wait for it. Opening the fit menu and reading the four
     * options takes longer than four seconds, and the chrome vanishing underneath
     * takes the menu with it — the tap that follows lands on the page and turns it.
     */
    var isMenuOpen by remember { mutableStateOf(false) }

    /** Set when the reader turns past the last page. */
    var hasReachedEnd by remember { mutableStateOf(false) }

    // `native-experience`: haptics, for the two events that have nothing else to
    // announce them. Not for a page turn — a comic read at speed is two hundred of
    // those, and a buzz on each is a defect.
    val haptics = rememberHaptics()

    /** Whether the thumbnail strip is open. */
    var isBrowsingThumbnails by remember { mutableStateOf(false) }

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
    // The strip and an open menu both count as interaction: reading either takes
    // longer than four seconds, and the chrome vanishing underneath would take them
    // with it.
    LaunchedEffect(
        isChromeVisible,
        position,
        isMenuOpen,
        isBrowsingThumbnails,
        isAdjusting,
        scrubbing,
    ) {
        // Not while the adjustment controls are open, and not mid-scrub: a reader dragging
        // a slider has not stopped interacting because they have not touched the page, and
        // a drag no longer moves `position` for the countdown to notice.
        if (!isChromeVisible || isMenuOpen || isBrowsingThumbnails || isAdjusting) {
            return@LaunchedEffect
        }
        if (scrubbing != null) return@LaunchedEffect
        delay(CHROME_TIMEOUT_MILLIS)
        isChromeVisible = false
    }

    // `comic-reader`: the prefetch window narrows "under memory pressure rather than the
    // app being terminated". Android reports pressure through the context's component
    // callbacks and never reports it lifting, so the all-clear is tied to the reader
    // coming back to the foreground instead — see `noteMemoryPressure`.
    val context = LocalContext.current
    DisposableEffect(context, viewModel) {
        val callbacks = object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                scope.launch { viewModel.noteMemoryPressure(trimPressure(level), at = readingPage) }
            }

            override fun onConfigurationChanged(newConfig: Configuration) = Unit

            @Deprecated("Superseded by onTrimMemory, and still called on older systems.")
            override fun onLowMemory() {
                scope.launch {
                    viewModel.noteMemoryPressure(MemoryPressure.CRITICAL, at = readingPage)
                }
            }
        }
        context.registerComponentCallbacks(callbacks)
        onDispose { context.unregisterComponentCallbacks(callbacks) }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        scope.launch { viewModel.noteMemoryPressure(MemoryPressure.NORMAL, at = readingPage) }
    }

    // The pager owns its position and the model follows, in one direction only.
    LaunchedEffect(position) {
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
            if (!hasReachedEnd) haptics.play(StoryArcFeedback.COMPLETION)
            hasReachedEnd = true
        } else {
            // The one page turn that earns a haptic is the one that does not happen.
            // Nothing on screen says the reader is already at the first page — the page
            // simply stays put, which is indistinguishable from a missed tap.
            haptics.play(StoryArcFeedback.REFUSAL)
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

    /** Goes back to where the reader was before the last jump. */
    fun returnFromJump() {
        val mark = pageReturn.mark ?: return
        pageReturn = pageReturn.taken()
        scope.launch { paging.goTo(displayIndex(mark), animate = false) }
    }

    fun handleTap(point: Offset, size: IntSize) {
        val edge = size.width * EDGE_ZONE_FRACTION
        val target = when {
            point.x < edge -> paging.current - 1
            point.x > size.width - edge -> paging.current + 1
            else -> {
                isChromeVisible = !isChromeVisible
                return
            }
        }
        turn(target)
    }

    // `page-transitions`: the volume buttons turn pages "where enabled in settings". A
    // volume key never reaches Compose — it arrives at the activity, and only the activity
    // can consume it before the system changes the volume — so the reader offers a handler
    // and the host decides whether to call it.
    val volume = LocalVolumeTurns.current
    DisposableEffect(volume, isRightToLeft) {
        volume.turn = { forward ->
            // In turn-space, so a right-to-left publication still advances on volume-up.
            // The display order is already reversed, which is why this is a step of one
            // either way rather than a sign flip.
            turn(paging.current + if (forward) 1 else -1)
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
        .onKeyEvent { event ->
            if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
            val step = when (event.key) {
                Key.DirectionLeft, Key.PageUp -> -1
                Key.DirectionRight, Key.PageDown, Key.Spacebar -> 1
                else -> return@onKeyEvent false
            }
            turn(paging.current + step)
            true
        }

    /** One page, however it is being presented. */
    @Composable
    fun SinglePage(index: Int, stitch: ScrollAxis?, onTap: (Offset, IntSize) -> Unit) {
        // The zoom-resolution copy when one is held, the display one otherwise.
        val bitmap = viewModel.displayImage(index)
        val trims = adjustments.cropsBorders && index !in uncropped
        when {
            bitmap != null -> ZoomablePage(
                // Cropped before it becomes an `ImageBitmap`: the trim changes the page's
                // size, which everything downstream measures from.
                bitmap = remember(bitmap, trims) {
                    bitmap.cropped(trims).asImageBitmap()
                },
                pageId = pages.getOrNull(index)?.path ?: index.toString(),
                // The page number, not the archive entry's path. TalkBack read
                // "page10.png" aloud, which names a file inside a CBZ rather than a
                // page — and the reader never chose that name.
                contentDescription = stringResource(R.string.reader_page_label, index + 1, pages.size),
                fit = fit,
                adjustments = adjustments,
                onTap = onTap,
                // In a continuous scroll a page takes the height its own proportions
                // ask for. Fitting each one to the screen instead would put a band of
                // background between every pair, which is the opposite of the
                // "stitched with no gap" `comic-reader` asks for.
                stitch = stitch,
                onZoom = { scale -> viewModel.holdZoom(scale, index) },
            )
            // A page that is not drawn still has to accept a tap: a reader who lands
            // on a skipped page must be able to turn away from it.
            // `page-transitions`: a turn runs "against a placeholder holding the
            // correct aspect ratio, so the turn does not jump when the content
            // arrives". In a paged mode the page is screen-sized either way; in a
            // stitched scroll a screen-sized placeholder becomes a page-sized item
            // the moment it decodes, and every page below it lurches.
            else -> Box(
                modifier = Modifier
                    .then(
                        when (stitch) {
                            ScrollAxis.VERTICAL -> Modifier
                                .fillMaxWidth()
                                .aspectRatio(PAGE_RATIO)
                            ScrollAxis.HORIZONTAL -> Modifier
                                .fillMaxHeight()
                                .aspectRatio(PAGE_RATIO)
                            null -> Modifier.fillMaxSize()
                        },
                    )
                    .tappable(onTap),
                contentAlignment = Alignment.Center,
            ) {
                if (viewModel.isUnavailable(index)) {
                    // Said, not blank, and named. `publication-formats` requires an
                    // undecodable page to show "a placeholder naming the codec": one
                    // page saying JPEG among ninety-nine that drew is a damaged entry in
                    // the file, and every page saying JPEG XL is a format this device
                    // has no decoder for. With no name the two look identical, and the
                    // only thing a reader could conclude was that the app was broken.
                    val codec = viewModel.codecName(index)
                    Message(
                        if (codec != null) {
                            stringResource(R.string.reader_page_unavailable_codec, codec)
                        } else {
                            stringResource(R.string.reader_page_unavailable)
                        },
                    )
                } else {
                    DelayedProgressIndicator()
                }
            }
        }
    }

    /**
     * One slot: a page, or two facing pages.
     *
     * `comic-reader`: a pair is shown "side by side in the correct order for the reading
     * direction". Reading order is the publication's own either way — a manga spread
     * reads 4 then 5 exactly as a western one does — so only the screen order flips, and
     * it flips here rather than anywhere the pages are counted.
     */
    @Composable
    fun Page(display: Int, stitch: ScrollAxis? = null) {
        val spread = layout.slotAt(slotIndex(display))
        val trailing = spread?.trailing
        if (trailing == null || stitch != null) {
            SinglePage(spread?.leading ?: 0, stitch, ::handleTap)
            return
        }
        val onScreen =
            if (isRightToLeft) listOf(trailing, spread.leading) else listOf(spread.leading, trailing)
        Row(Modifier.fillMaxSize()) {
            onScreen.forEachIndexed { half, index ->
                Box(
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    contentAlignment = Alignment.Center,
                ) {
                    SinglePage(index, stitch = null) { point, size ->
                        // The halves are equal, so a tap in one is a tap in the same place
                        // on a screen twice as wide. Without this the edge zones would be
                        // measured against half the screen, and the middle of a spread
                        // would turn the page.
                        handleTap(
                            Offset(if (half == 0) point.x else point.x + size.width, point.y),
                            IntSize(size.width * 2, size.height),
                        )
                    }
                }
            }
        }
    }

    // One container per mode, over one page body. `page-transitions` treats the mode
    // as a property of the container, which is exactly what this is: the pager brings
    // its own gesture and edge resistance, the fade has no container at all, the scroll
    // is a lazy list, and the curl is a shader over two decoded pages.
    if (choices.effective == PageTransition.PAGE_CURL) {
        CurledPages(
            page = viewModel.image(modelIndex(paging.current)),
            // The page underneath is the next *display* position, not the next page
            // number: in right-to-left the two run opposite ways, and a curl that
            // revealed the wrong side would be worse than no curl.
            beneath = viewModel.image(modelIndex(paging.current + 1)),
            isRightToLeft = isRightToLeft,
            matte = matte,
            onTurned = { turn(paging.current + 1) },
            onTap = ::handleTap,
            modifier = keyboard,
        )
    } else {
        when (paging) {
            is Paging.Paged -> HorizontalPager(state = paging.state, modifier = keyboard) { page ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Page(page)
                }
            }

            is Paging.Indexed -> AnimatedContent(
            targetState = paging.index.intValue,
            modifier = keyboard,
            // Short enough not to read as an animation, which is the whole point of
            // the name. `page-transitions` uses this as the Reduce Motion substitute,
            // so it must not become the thing it replaces.
            transitionSpec = {
                fadeIn(tween(FADE_MILLIS)) togetherWith fadeOut(tween(FADE_MILLIS))
            },
            label = "page",
        ) { page ->
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Page(page)
            }
        }

            is Paging.Scrolled -> if (choices.effective == PageTransition.VERTICAL_SCROLL) {
                LazyColumn(state = paging.state, modifier = keyboard) {
                    items(slotCount) { index ->
                        // `comic-reader` asks for the separator *between* pages, so the
                        // first page does not get one — a band above page one is a
                        // margin, not a separator.
                        if (settings.showsPageSeparator && index > 0) {
                            PageSeparator(ScrollAxis.VERTICAL, matte)
                        }
                        Page(index, stitch = ScrollAxis.VERTICAL)
                    }
                }
            } else {
                LazyRow(state = paging.state, modifier = keyboard) {
                    items(slotCount) { index ->
                        if (settings.showsPageSeparator && index > 0) {
                            PageSeparator(ScrollAxis.HORIZONTAL, matte)
                        }
                        Page(index, stitch = ScrollAxis.HORIZONTAL)
                    }
                }
            }
        }
    }

    if (hasReachedEnd) {
        EndOfPublication(
            title = viewModel.publication.displayTitle,
            colours = coverColours,
            next = nextInSeries,
            onOpenNext = onOpen,
            onBack = { hasReachedEnd = false },
            onClose = onClose,
        )
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
        )
    }

    AnimatedVisibility(visible = isChromeVisible, enter = fadeIn(), exit = fadeOut()) {
        // Inside the system bars. The reader draws edge to edge so the page fills the
        // screen, and without this the top row sat under the status bar's own gesture
        // strip: the system took the touch and the buttons were all but unreachable.
        // Measured on an emulator, where only the lowest sliver of each button worked.
        Box(Modifier.fillMaxSize().safeDrawingPadding()) {
            CloseButton(onClose)
            if (count > 1) {
                ThumbnailToggle(
                    isOpen = isBrowsingThumbnails,
                    onToggle = { isBrowsingThumbnails = !isBrowsingThumbnails },
                    modifier = Modifier.align(Alignment.TopCenter),
                )
            }
            Row(modifier = Modifier.align(Alignment.TopEnd)) {
                TransitionMenu(
                    choices = choices,
                    showsSeparator = settings.showsPageSeparator,
                    onToggleSeparator = viewModel::choosePageSeparator,
                    // A scroll row is an axis choice: recording it as one is what
                    // makes the override stick, rather than leaving the axis implied
                    // and the mode disagreeing with it.
                    onChoose = { mode ->
                        val axis = mode.scrollAxis
                        if (axis != null) viewModel.choose(axis) else viewModel.choose(mode)
                    },
                    onOpenChange = { isMenuOpen = it },
                )
                FitMenu(
                    fit = fit,
                    onChange = onFitChange,
                    onOpenChange = { isMenuOpen = it },
                )
                // Only where there is a pairing to shift. `comic-reader` offers the
                // offset "for publications whose cover throws the pairing off", which is
                // a question that does not arise in portrait or in a scroll.
                if (layout.hasPairs) {
                    SpreadOffsetButton(
                        isOffset = settings.offsetsSpreads,
                        onToggle = { viewModel.chooseSpreadOffset(!settings.offsetsSpreads) },
                    )
                }
                AdjustButton(isNeutral = adjustments.isNeutral) { isAdjusting = true }
            }

            Column(
                // A band, for the same reason the pills carry a scrim: the page number
                // and the slider thumb are white and the page under them can be white.
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f))
                    .padding(horizontal = StoryArcSpace.md, vertical = StoryArcSpace.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (isBrowsingThumbnails) {
                    ThumbnailStrip(
                        viewModel = viewModel,
                        pageCount = count,
                        currentIndex = modelIndex(paging.current),
                        onSelect = { index ->
                            isBrowsingThumbnails = false
                            // A jump, like the slider's: it leaves the same mark, so the
                            // way back from a mis-tap in a three-hundred-page strip is
                            // one control.
                            jump(index)
                        },
                        modifier = Modifier.padding(bottom = StoryArcSpace.sm),
                    )
                }

                // Down here with the page count rather than in the top row, which on a
                // phone is already the way out of the reader and three controls wide.
                Row(verticalAlignment = Alignment.CenterVertically) {
                    DirectionMenu(
                        direction = direction,
                        onChoose = viewModel::choose,
                        onOpenChange = { isMenuOpen = it },
                    )
                    OrientationToggle(
                        isLocked = isOrientationLocked,
                        onToggle = { isOrientationLocked = !isOrientationLocked },
                    )
                }

                ChapterRow(
                    previous = previousInSeries,
                    next = nextInSeries,
                    onOpen = onOpen,
                )

                // The scrub target while a drag is in progress, and where the reader
                // actually is otherwise. `comic-reader` asks for "the page number and
                // total" beside the thumbnail, and during a drag the number a reader
                // wants is the one they are heading for.
                val sliderIndex = scrubbing ?: modelIndex(paging.current)

                scrubbing?.let { target ->
                    ScrubThumbnail(
                        viewModel = viewModel,
                        index = target,
                        modifier = Modifier.padding(bottom = StoryArcSpace.xs),
                    )
                }

                Surface(
                    color = Color.White.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(percent = 50),
                ) {
                    Text(
                        text = stringResource(R.string.reader_page, sliderIndex + 1, count),
                        style = MaterialTheme.typography.labelLarge,
                        color = Color.White,
                        modifier = Modifier.padding(
                            horizontal = StoryArcSpace.md,
                            vertical = StoryArcSpace.xs,
                        ),
                    )
                }

                if (count > 1) {
                    val sliderName = stringResource(R.string.reader_page_slider)
                    val pageLabel = stringResource(R.string.reader_page, sliderIndex + 1, count)
                    // Bound to the *publication's* page number, not the pager's
                    // position. In right-to-left the two run opposite ways, and a
                    // slider whose left end is the last page would be a puzzle.
                    //
                    // The drag writes to `scrubbing` and the release moves the reader,
                    // which is what `comic-reader` asks for and also what stops a scrub
                    // across a long comic asking the archive for every page on the way.
                    // TalkBack's own adjustment lands here too: Compose calls the
                    // finished callback after an accessibility action, so a stepped
                    // slider still turns the page.
                    Slider(
                        value = sliderIndex.toFloat(),
                        onValueChange = { value -> scrubbing = value.roundToInt() },
                        onValueChangeFinished = {
                            scrubbing?.let(::jump)
                            scrubbing = null
                        },
                        valueRange = 0f..(count - 1).toFloat(),
                        steps = (count - 2).coerceAtLeast(0),
                        colors = SliderDefaults.colors(
                            thumbColor = Color.White,
                            activeTrackColor = Color.White,
                            inactiveTrackColor = Color.White.copy(alpha = 0.3f),
                        ),
                        // Named, and reading the page rather than the range percent
                        // Compose announces by default.
                        modifier = Modifier.fillMaxWidth().semantics {
                            contentDescription = sliderName
                            stateDescription = pageLabel
                        },
                    )
                }

                // The way back from a jump. It names the page rather than saying "Back",
                // because by the time a reader notices they have lost their place they no
                // longer remember what it was.
                pageReturn.mark?.let { mark ->
                    TextButton(
                        onClick = ::returnFromJump,
                        colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Undo,
                            contentDescription = null,
                            modifier = Modifier.padding(end = StoryArcSpace.xs),
                        )
                        Text(stringResource(R.string.reader_return, mark + 1))
                    }
                }

                SkippedNotice(skipped)
            }
        }
    }
}

/**
 * How many entries the archive could not give us, when any.
 *
 * `publication-formats`: a damaged archive opens "whatever pages it can read and states
 * how many were skipped, rather than refusing the whole publication". The opening half
 * was already true and the *stating* half was not — the count reached the view model and
 * stopped there, so a reader met a comic that was quietly eight pages short and had
 * nothing to tell them why.
 *
 * In the chrome rather than over the artwork: it is a fact about the file, not about the
 * page in front of the reader, and the non-negotiable is that chrome recedes. So it
 * arrives with the controls, sits under the page counter it qualifies, and leaves with
 * them four seconds later.
 *
 * iOS's `skippedNotice` is the same line in the same place.
 */
@Composable
private fun SkippedNotice(count: Int) {
    if (count <= 0) return
    Surface(
        color = Color.White.copy(alpha = 0.2f),
        shape = RoundedCornerShape(percent = 50),
        modifier = Modifier.padding(top = StoryArcSpace.xs),
    ) {
        Text(
            text = pluralStringResource(R.plurals.reader_skipped, count, count),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White,
            modifier = Modifier.padding(
                horizontal = StoryArcSpace.md,
                vertical = StoryArcSpace.xs,
            ),
        )
    }
}

/**
 * One page, fitted and zoomable.
 *
 * `comic-reader`: "the page zooms about the pinch centre, pans within bounds, and
 * double-tap toggles between fit and a zoomed level centred on the tapped point".
 *
 * `canPan` is what makes this coexist with the pager: at fit scale the page
 * declines the drag and the pager turns the page, and once zoomed the page takes
 * it. Without that the reader can either zoom or turn pages, never both.
 */
@Composable
private fun ZoomablePage(
    bitmap: ImageBitmap,
    /**
     * What page this is, as distinct from which decode of it is in hand.
     *
     * The zoom is keyed on this rather than on [bitmap] because one page now has two
     * decodes — the display-resolution one and the copy re-decoded for a held zoom — and
     * keying the zoom on the bitmap would put the page back to fit the instant the
     * sharper copy arrived, which drops the zoom that asked for it and flips the two
     * decodes against each other for ever.
     */
    pageId: String,
    contentDescription: String?,
    fit: PageFit,
    adjustments: ImageAdjustments,
    onTap: (Offset, IntSize) -> Unit,
    /**
     * How far the reader has magnified the page, reported once a pinch settles.
     *
     * `publication-formats` asks for a page to be "re-decoded at higher resolution when
     * the user zooms", and this composable is the only thing that knows how far. Sent
     * after the scale has held still rather than on every frame: a pinch produces dozens
     * of changes a second, and a full-page decode per frame would be the opposite of
     * making the page feel sharp.
     */
    onZoom: suspend (Float) -> Unit,
    modifier: Modifier = Modifier,
    /**
     * The axis this page is stitched along, or null when it is a page on its own.
     *
     * A stitched page fills the scroll's *cross* axis and takes whatever it needs
     * along the scroll axis, so consecutive pages meet with no gap — `comic-reader`
     * asks for them "stitched with no gap by default". Fitting each one to the screen
     * instead would leave a band of background between every pair, and stitching
     * along the wrong axis leaves a row of slivers.
     *
     * Zoom and pan are off here: the scroll owns the drag, and two things claiming it
     * is how a reader ends up able to do neither.
     */
    stitch: ScrollAxis? = null,
) {
    // Rebuilt only when the reader moves a control, not on every frame of a scroll.
    val colours = remember(adjustments) { adjustments.colourFilter() }
    val sharpen = remember(adjustments) { adjustments.sharpeningEffect() }

    var size by remember { mutableStateOf(IntSize.Zero) }
    val page = remember(bitmap, size) {
        PageBounds.of(IntSize(bitmap.width, bitmap.height), size)
    }

    // Back to the fit whenever the page or the mode changes. `comic-reader` wants
    // the *zoom* carried across a turn in fit-to-width mode, and that is what
    // carrying the mode does — the next page opens at its own top, magnified the
    // same way, rather than at whatever corner of the last page was on screen.
    //
    // The page, not the bitmap: see [pageId].
    //
    // `size` belongs in that key for a second reason, and dropping it to keep a pinch
    // across a rotation would cost more than it bought: the first composition happens
    // before the layout has measured anything, so the fit taken there is against a
    // viewport of zero. Keying on the measured size is what makes that one thrown away
    // and re-taken the moment `onSizeChanged` reports a real one. iOS had to be told
    // this explicitly — see `AppliedFit` there — because UIKit is asked once and does
    // not ask again.
    var zoom by remember(pageId, fit, size) { mutableStateOf(PageZoom.fitting(fit, page)) }

    val transform = rememberTransformableState { centroid, zoomChange, panChange, _ ->
        zoom = zoom.pinched(centroid, zoomChange, panChange, page)
    }

    // The debounce, and the whole of it: keying the effect on the scale cancels the
    // pending decode every time the pinch moves, so only the magnification the reader
    // stopped at is ever asked for. iOS gets the same restraint from UIKit, which
    // reports `scrollViewDidEndZooming` once at the end of the gesture.
    LaunchedEffect(pageId, zoom.scale) {
        delay(ZOOM_SETTLE_MILLIS)
        onZoom(zoom.scale)
    }

    if (stitch != null) {
        Image(
            bitmap = bitmap,
            contentDescription = contentDescription,
            colorFilter = colours,
            contentScale = if (stitch == ScrollAxis.VERTICAL) {
                ContentScale.FillWidth
            } else {
                ContentScale.FillHeight
            },
            modifier = if (stitch == ScrollAxis.VERTICAL) {
                // Full width, natural height: what lets a webtoon read as one strip.
                modifier.fillMaxWidth()
            } else {
                // Full height, natural width: pages side by side, edge to edge.
                modifier.fillMaxHeight()
            }
                .graphicsLayer { renderEffect = sharpen }
                .tappable(onTap = onTap),
        )
        return
    }

    Image(
        bitmap = bitmap,
        contentDescription = contentDescription,
        colorFilter = colours,
        // Fit, not fill: cropping a comic page loses artwork, and `comic-reader`
        // treats the whole page as the unit. Zoom starts from that fit.
        contentScale = ContentScale.Fit,
        modifier = modifier
            .fillMaxSize()
            .onSizeChanged { size = it }
            // `canPan` is what makes this coexist with the pager: the page declines
            // a drag it has no slack for, and the pager turns the page instead.
            .transformable(state = transform, canPan = { page.slack(zoom.scale) != Offset.Zero })
            // Centred on what was tapped, not on the middle of the screen: the
            // point of a double-tap is to magnify *that* panel.
            .tappable(onTap = onTap, onDoubleTap = { zoom = zoom.doubleTapped(it, page) })
            .graphicsLayer {
                scaleX = zoom.scale
                scaleY = zoom.scale
                translationX = zoom.offset.x
                translationY = zoom.offset.y
                renderEffect = sharpen
            },
    )
}

/**
 * Taps, reported with the size they landed in so the caller can find the edges.
 *
 * Not `detectTapGestures`. That detector delays *every* tap by the double-tap
 * timeout whenever a double-tap handler is present, and a page turn that arrives
 * 300 ms after the finger lifts feels broken — `comic-reader` treats the edge tap
 * as a turn, not as a menu.
 *
 * So the wait is spent only where it buys something: a tap in the middle might be
 * the first half of a double-tap, and waiting there costs nothing a reader would
 * notice. A tap on an edge cannot be, and fires at once.
 *
 * The size comes from `PointerInputScope.size`: inside the gesture the layout is
 * already measured, and one fewer piece of state is one fewer thing to get out of
 * step.
 */
private fun Modifier.tappable(
    onTap: (Offset, IntSize) -> Unit,
    onDoubleTap: ((Offset) -> Unit)? = null,
): Modifier = this.pointerInput(onTap, onDoubleTap) {
    awaitEachGesture {
        awaitFirstDown()
        val up = waitForUpOrCancellation() ?: return@awaitEachGesture
        val point = up.position

        if (onDoubleTap == null || isEdgeTap(point, size)) {
            onTap(point, size)
            return@awaitEachGesture
        }

        val second = withTimeoutOrNull(viewConfiguration.doubleTapTimeoutMillis) {
            awaitFirstDown()
        }
        if (second == null) {
            onTap(point, size)
        } else {
            waitForUpOrCancellation()
            onDoubleTap(second.position)
        }
    }
}

private fun PointerInputScope.isEdgeTap(point: Offset, area: IntSize): Boolean {
    val edge = area.width * EDGE_ZONE_FRACTION
    return point.x < edge || point.x > area.width - edge
}

/**
 * Moving between the publications of a series, from inside the reader.
 *
 * `comic-reader`: "WHEN a publication has internal chapter markers, or is one chapter of
 * a series THEN the reader offers previous and next chapter actions without returning to
 * the library". A local library knows the second of those two — a series and its order —
 * so a chapter here is a publication, and the row is absent entirely for a book that
 * belongs to no series.
 *
 * iOS's `chapterRow` is the same row.
 */
@Composable
private fun ChapterRow(
    previous: Publication?,
    next: Publication?,
    onOpen: (Publication) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (previous == null && next == null) return
    Row(
        modifier = modifier.padding(bottom = StoryArcSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        ChapterButton(previous, Icons.Filled.SkipPrevious, R.string.reader_chapter_previous, onOpen)
        ChapterButton(next, Icons.Filled.SkipNext, R.string.reader_chapter_next, onOpen)
    }
}

/**
 * One chapter button, disabled at the end of the run rather than absent.
 *
 * The first and the last issue of a series each have one neighbour, and a row that
 * changed shape between them would move the other button under the finger. A disabled
 * control also says there is nothing that way, which a missing one does not.
 *
 * Skip-previous and skip-next rather than a chevron: this is the track-skip idiom, and it
 * does not mirror for a right-to-left publication — the series still runs from its first
 * issue to its last whichever way its pages do.
 */
@Composable
private fun ChapterButton(
    destination: Publication?,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    labelRes: Int,
    onOpen: (Publication) -> Unit,
) {
    IconButton(
        onClick = { destination?.let(onOpen) },
        enabled = destination != null,
    ) {
        Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
            Icon(
                imageVector = icon,
                contentDescription = stringResource(labelRes),
                // Dimmed rather than gone: an end of the run reads as "nothing that way",
                // which a control that vanished would not say at all.
                tint = if (destination != null) Color.White else Color.White.copy(alpha = 0.35f),
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

/**
 * The break between two pages in a continuous scroll.
 *
 * `comic-reader`: pages are "stitched with no gap by default, with an option to show a
 * separator". A band of the matte with a hairline through it, rather than a hairline on
 * its own: a black line between two black-bordered pages is invisible and so is a white
 * one between two white ones, and the matte is the colour the reader has already said
 * belongs between the artwork and the screen.
 *
 * iOS's `PageSeparator` is the same band.
 */
@Composable
private fun PageSeparator(
    axis: ScrollAxis,
    /** What shows around the page, which is what shows between two of them. */
    matte: Color,
    modifier: Modifier = Modifier,
) {
    // Enough to read as a deliberate break at arm's length, and not so much that a
    // webtoon stops reading as one strip.
    val band = 10.dp
    Box(
        modifier = modifier
            .then(
                if (axis == ScrollAxis.VERTICAL) {
                    Modifier.fillMaxWidth().height(band)
                } else {
                    Modifier.fillMaxHeight().width(band)
                },
            )
            .background(matte),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .then(
                    if (axis == ScrollAxis.VERTICAL) {
                        Modifier.fillMaxWidth().height(1.dp)
                    } else {
                        Modifier.fillMaxHeight().width(1.dp)
                    },
                )
                .background(LocalStoryArcPalette.current.borderSubtle),
        )
    }
}

/**
 * Shifts which pages are paired, for a publication whose cover throws the pairing off.
 *
 * iOS's spread-offset button is the same control.
 */
@Composable
private fun SpreadOffsetButton(
    isOffset: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onToggle, modifier = modifier.padding(StoryArcSpace.md)) {
        Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
            Icon(
                imageVector = Icons.Filled.ViewColumn,
                contentDescription = stringResource(R.string.reader_spreads_offset),
                tint = if (isOffset) LocalStoryArcPalette.current.accent else Color.White,
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

/** Opens and closes the page strip. */
@Composable
private fun ThumbnailToggle(
    isOpen: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onToggle, modifier = modifier.padding(StoryArcSpace.md)) {
        Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
            Icon(
                imageVector = Icons.Filled.GridView,
                contentDescription = stringResource(R.string.reader_thumbnails),
                tint = if (isOpen) LocalStoryArcPalette.current.accent else Color.White,
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

/**
 * How the page is sized. `comic-reader` names the four modes.
 */
@Composable
private fun FitMenu(
    fit: PageFit,
    onChange: (PageFit) -> Unit,
    onOpenChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    Box(modifier) {
        IconButton(onClick = { open = true }, modifier = Modifier.padding(StoryArcSpace.md)) {
            Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
                Icon(
                    imageVector = Icons.Filled.Fullscreen,
                    contentDescription = stringResource(R.string.reader_fit),
                    tint = Color.White,
                    modifier = Modifier.padding(StoryArcSpace.sm),
                )
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            PageFit.entries.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(stringResource(candidate.labelRes)) },
                    leadingIcon = { RadioButton(selected = fit == candidate, onClick = null) },
                    onClick = {
                        onChange(candidate)
                        open = false
                    },
                )
            }
        }
    }
}

/**
 * Which way the pages run.
 *
 * `comic-reader` opens a publication in the direction its metadata declares and lets the
 * reader overrule that, for the series. Two rows and a radio, the same shape as [FitMenu]
 * rather than a bare toggle: metadata gets this wrong often enough that a reader who
 * suspects it needs to see which way the comic is running, not only be able to flip it.
 */
@Composable
private fun DirectionMenu(
    direction: ReadingDirection,
    onChoose: (ReadingDirection) -> Unit,
    onOpenChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    Box(modifier) {
        IconButton(onClick = { open = true }, modifier = Modifier.padding(StoryArcSpace.md)) {
            Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
                Icon(
                    imageVector = Icons.Filled.SwapHoriz,
                    contentDescription = stringResource(R.string.reader_direction),
                    tint = Color.White,
                    modifier = Modifier.padding(StoryArcSpace.sm),
                )
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            ReadingDirection.entries.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(stringResource(candidate.labelRes)) },
                    leadingIcon = { RadioButton(selected = direction == candidate, onClick = null) },
                    onClick = {
                        onChoose(candidate)
                        open = false
                    },
                )
            }
        }
    }
}

/**
 * Holds the screen at the way up it is now.
 *
 * `comic-reader` scopes the lock to the reader, so it is a button here rather than a row
 * in Settings. Its name says what pressing it would do rather than what the state is:
 * with no label on screen beside the icon, that sentence is all TalkBack has to go on.
 */
@Composable
private fun OrientationToggle(
    isLocked: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onToggle, modifier = modifier.padding(StoryArcSpace.md)) {
        Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
            Icon(
                imageVector = if (isLocked) {
                    Icons.Filled.ScreenLockRotation
                } else {
                    Icons.Filled.ScreenRotation
                },
                contentDescription = stringResource(
                    if (isLocked) R.string.reader_orientation_unlock else R.string.reader_orientation_lock,
                ),
                tint = if (isLocked) LocalStoryArcPalette.current.accent else Color.White,
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

/**
 * The page-transition picker.
 *
 * Four rows, and `page-transitions` is specific about what a row that cannot run
 * looks like: "shown unavailable with a one-line reason, never silently absent". So a
 * row disabled by reduced motion stays, greyed, with the reason under it — a control
 * that vanishes teaches the reader nothing.
 *
 * Curl is the one exception, and the spec draws that line itself: where the *device*
 * cannot honour it, Curl is "absent from the picker on that device… with the reason
 * stated once in plain language — naming the requirement, not an API level". A
 * permanently dead row is furniture; a sentence is an explanation.
 */
@Composable
private fun TransitionMenu(
    choices: TransitionChoices,
    onChoose: (PageTransition) -> Unit,
    onOpenChange: (Boolean) -> Unit,
    /** Whether a continuous scroll draws a line where one page ends and the next begins. */
    showsSeparator: Boolean,
    onToggleSeparator: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    Box(modifier) {
        IconButton(onClick = { open = true }, modifier = Modifier.padding(StoryArcSpace.md)) {
            Surface(color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f), shape = CircleShape) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.MenuBook,
                    contentDescription = stringResource(R.string.reader_transition),
                    tint = Color.White,
                    modifier = Modifier.padding(StoryArcSpace.sm),
                )
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.offered.forEach { mode ->
                val reason = choices.unavailable[mode]
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(stringResource(mode.labelRes))
                            if (reason != null) {
                                Text(
                                    text = stringResource(reason.labelRes),
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            }
                        }
                    },
                    leadingIcon = {
                        RadioButton(
                            selected = choices.chosen == mode,
                            onClick = null,
                            enabled = reason == null,
                        )
                    },
                    enabled = reason == null,
                    onClick = {
                        onChoose(mode)
                        open = false
                    },
                )
            }
            // Only where there are stitched pages to separate. In a paged mode there is a
            // whole screen between one page and the next already.
            if (choices.effective.scrollAxis != null) {
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.reader_separator)) },
                    leadingIcon = { Checkbox(checked = showsSeparator, onCheckedChange = null) },
                    onClick = { onToggleSeparator(!showsSeparator) },
                )
            }
            if (choices.curlIsAbsent) {
                // Once, and in the reader's language rather than the platform's.
                DropdownMenuItem(
                    text = {
                        Text(
                            text = stringResource(R.string.reader_transition_no_curl),
                            style = MaterialTheme.typography.labelSmall,
                        )
                    },
                    enabled = false,
                    onClick = {},
                )
            }
        }
    }
}

/** How the transition modes are named on screen. */
private val PageTransition.labelRes: Int
    get() = when (this) {
        PageTransition.PAGE_CURL -> R.string.reader_transition_curl
        PageTransition.SLIDE -> R.string.reader_transition_slide
        PageTransition.FAST_FADE -> R.string.reader_transition_fade
        PageTransition.VERTICAL_SCROLL -> R.string.reader_transition_scroll_vertical
        PageTransition.HORIZONTAL_SCROLL -> R.string.reader_transition_scroll_horizontal
    }

/** Why a mode cannot run, in one line. */
private val TransitionUnavailability.labelRes: Int
    get() = when (this) {
        TransitionUnavailability.REDUCE_MOTION -> R.string.reader_transition_reduce_motion
        // A comic page is already an image, so this reason cannot arise here. It is
        // named rather than swallowed by an `else`, so that adding a third reason still
        // breaks this file rather than silently showing the wrong sentence.
        TransitionUnavailability.REFLOWABLE_TEXT -> R.string.reader_transition_reflowable
    }

/**
 * Which way the pages run, named the way a reader would say it.
 *
 * Right-to-left reuses the sentence TalkBack already reads out on entering a manga,
 * because it is the same fact and a second wording of it would be one to keep in step
 * for nothing.
 */
private val ReadingDirection.labelRes: Int
    get() = when (this) {
        ReadingDirection.LEFT_TO_RIGHT -> R.string.reader_left_to_right
        ReadingDirection.RIGHT_TO_LEFT -> R.string.reader_right_to_left
    }

/**
 * How the fit modes are named on screen.
 *
 * The enum lives in `:core:model` and carries no resources: the domain has no
 * business holding UI copy.
 */
private val PageFit.labelRes: Int
    get() = when (this) {
        PageFit.SCREEN -> R.string.reader_fit_screen
        PageFit.WIDTH -> R.string.reader_fit_width
        PageFit.HEIGHT -> R.string.reader_fit_height
        PageFit.ORIGINAL -> R.string.reader_fit_original
    }

/**
 * What the reader shows after the last page.
 *
 * `native-experience` puts a cover-derived accent and background tint "on a publication
 * detail screen or the reader". This screen is where the reader can honour that:
 * everywhere else in it the artwork is *on* screen, and the non-negotiable is that chrome
 * over a page never tints. Here the page is behind a near-opaque sheet, so the colour has
 * somewhere to go.
 *
 * `comic-reader`: "an end screen offers the next publication in the series or
 * reading list, marks this one finished". Marking is already done — the last page
 * records `isFinished` as it is turned to, because a reader who closes the app on
 * the last page has still finished it.
 *
 * Deleting the download is offered by the same scenario and is not here: there are
 * no downloads yet, and a button that deletes nothing is worse than none.
 */
@Composable
private fun EndOfPublication(
    title: String,
    colours: CoverColours?,
    next: Publication?,
    onOpenNext: (Publication) -> Unit,
    onBack: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            // The wash, fading to black, and still near-opaque: the last page stays
            // faintly visible behind it, which is what says this screen is over the book
            // rather than after it.
            .background(
                brush = Brush.verticalGradient(
                    listOf(matteColour(colours?.wash), Color.Black),
                ),
                alpha = 0.92f,
            )
            .padding(StoryArcSpace.gutter),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg, Alignment.CenterVertically),
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            Text(
                text = stringResource(R.string.reader_end_finished),
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
            )
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
            )
        }

        if (next != null) {
            // The cover's accent, or the brand's. Never the raw extracted colour — what
            // `CoverColours` carries has already been adjusted to clear the floor, and
            // what is written on it was chosen for it rather than assumed to be white.
            Button(
                onClick = { onOpenNext(next) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = colours?.accent?.let { matteColour(it) }
                        ?: LocalStoryArcPalette.current.accent,
                    contentColor = colours?.onAccent?.let { matteColour(it) } ?: Color.White,
                ),
            ) {
                Text(stringResource(R.string.reader_end_next, next.displayTitle))
            }
        }

        // Wrapping, not a Row: at a 2x font scale "Back to the last page" takes the
        // whole width and left the Library button a few dp wide.
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            // White, not the theme's accent: this overlay is near-black whatever
            // the app's appearance, and the accent on it fails contrast.
            val labels = ButtonDefaults.textButtonColors(contentColor = Color.White)
            TextButton(onClick = onBack, colors = labels) {
                Text(stringResource(R.string.reader_end_back))
            }
            TextButton(onClick = onClose, colors = labels) {
                Text(stringResource(R.string.reader_end_library))
            }
        }
    }
}

/**
 * A spinner that waits before it appears.
 *
 * `comic-reader`: "a progress indicator appears only after 400 ms". A page that
 * decodes in 30 ms should not flash a spinner on its way — the flash reads as a
 * stutter, which is the opposite of what the indicator is for.
 */
@Composable
private fun DelayedProgressIndicator() {
    var isVisible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(SPINNER_DELAY_MILLIS)
        isVisible = true
    }
    if (isVisible) CircularProgressIndicator(color = Color.White)
}

@Composable
private fun Message(text: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier.padding(StoryArcSpace.gutter),
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = Color.White.copy(alpha = 0.7f))
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
    }
}

/** A quarter of the width each side: hittable on a phone, and the centre still has room. */
/**
 * The colour behind the page.
 *
 * A comic is read against its own artwork, so black is the default and a *preset* never
 * reaches here — a preset is a typographic theme and its paper colour means nothing behind
 * a page of art. Only a colour the reader chose explicitly applies, which is what
 * `reading-themes` means by "the area around the page and not the page itself".
 */
internal fun matteColour(hex: String?): Color {
    val text = hex?.removePrefix("#") ?: return Color.Black
    val value = text.toLongOrNull(16) ?: return Color.Black
    return Color(
        red = ((value shr 16) and 0xFF) / 255f,
        green = ((value shr 8) and 0xFF) / 255f,
        blue = (value and 0xFF) / 255f,
    )
}

/**
 * What one of Android's seven trim levels means in the three states the reader knows.
 *
 * `TRIM_MEMORY_RUNNING_CRITICAL` and everything above it — including the levels raised
 * once the app is no longer in front — are the ones where the system is choosing what to
 * end. `RUNNING_MODERATE` and `RUNNING_LOW` are a request rather than a threat.
 *
 * The running levels are deprecated as of API 35, which stopped delivering them, and are
 * still what an API 31 to 34 device sends — and ADR-0003 puts the floor at 31. So they
 * are read rather than ignored, and a device that never sends them simply never narrows
 * the window until its UI is hidden.
 *
 * iOS's `MemoryPressureSource` maps the same three states out of a dispatch source.
 */
@Suppress("DEPRECATION")
internal fun trimPressure(level: Int): MemoryPressure = when {
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> MemoryPressure.CRITICAL
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> MemoryPressure.WARNING
    else -> MemoryPressure.NORMAL
}

private const val EDGE_ZONE_FRACTION = 0.25f

/**
 * The cross-dissolve, short enough not to read as an animation.
 *
 * `page-transitions` uses Fast fade as the Reduce Motion substitute as well as a
 * mode in its own right, so it must not become the thing it replaces. 140 ms is
 * about the shortest a dissolve can be and still not look like a cut.
 */
/**
 * A page's shape before it is decoded.
 *
 * Its real proportions are unknown until it is read, and a comic page is close enough
 * to two by three that the difference is not what a reader notices — an item that
 * changed height by a factor of one and a half is.
 */
private const val PAGE_RATIO = 2f / 3f

/**
 * How long a pinch has to hold still before the page behind it is re-decoded.
 *
 * Short enough that a reader who stops to look does not wait for the sharpening, long
 * enough that crossing four magnifications on the way to the one they wanted costs one
 * decode rather than four. iOS needs no equivalent: UIKit reports the end of the gesture
 * rather than every frame of it.
 */
private const val ZOOM_SETTLE_MILLIS = 180L

private const val FADE_MILLIS = 140

private const val CHROME_TIMEOUT_MILLIS = 4_000L

private const val SPINNER_DELAY_MILLIS = 400L
