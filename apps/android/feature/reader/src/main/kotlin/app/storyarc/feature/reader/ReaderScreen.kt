package app.storyarc.feature.reader

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.focusable
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.LocalVolumeTurns
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PageEntry
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.scrollAxis
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.persistence.ReaderPreferences
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

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
     * What follows this publication, and how to open it. Supplied by the app layer:
     * the reader does not know what a library is, and a feature module never
     * depends on another feature module.
     */
    nextInSeries: Publication? = null,
    onOpenNext: (Publication) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val pages by viewModel.pages.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()

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
            pages.isEmpty() -> {
                DelayedProgressIndicator()
                CloseButton(onClose)
            }
            else -> Pager(
                viewModel = viewModel,
                pages = pages,
                onClose = onClose,
                nextInSeries = nextInSeries,
                onOpenNext = onOpenNext,
                fit = fit,
                onFitChange = { fit = it },
                matte = matte,
            )
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.CloseButton(onClose: () -> Unit) {
    IconButton(
        onClick = onClose,
        modifier = Modifier.align(Alignment.TopStart).padding(StoryArcSpace.md),
    ) {
        Surface(color = Color.White.copy(alpha = 0.2f), shape = CircleShape) {
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
    nextInSeries: Publication?,
    onOpenNext: (Publication) -> Unit,
    fit: PageFit,
    onFitChange: (PageFit) -> Unit,
    /** What shows behind and beside the page. See [matteColour]. */
    matte: Color,
) {
    val count = pages.size
    val isRightToLeft = viewModel.readingDirection == ReadingDirection.RIGHT_TO_LEFT

    /**
     * A display position turned back into the publication's own page number.
     *
     * Right-to-left reverses the *display* order and maps the index here, so the
     * model keeps counting pages the way the publication does and the indicator
     * says "2 of 4" rather than "3 of 4" for the same page. Mirroring the pager
     * with a transform instead would fight the paging gesture — iOS learned that
     * the hard way, and the note is in ReaderView.swift.
     */
    fun modelIndex(display: Int) = if (isRightToLeft) count - 1 - display else display
    fun displayIndex(model: Int) = if (isRightToLeft) count - 1 - model else model

    // `page-transitions`: the mode "applies to the current publication immediately
    // without losing the reading position". Hoisted above the coordinator so a mode
    // change seeds the new container from where the reader already is.
    var position by remember { mutableIntStateOf(displayIndex(viewModel.initialIndex)) }
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val choices = viewModel.transitions(settings)
    val paging = rememberPaging(choices.effective, count, position)
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

    /** Whether the thumbnail strip is open. */
    var isBrowsingThumbnails by remember { mutableStateOf(false) }
    // The strip and an open menu both count as interaction: reading either takes
    // longer than four seconds, and the chrome vanishing underneath would take them
    // with it.
    LaunchedEffect(isChromeVisible, position, isMenuOpen, isBrowsingThumbnails) {
        if (!isChromeVisible || isMenuOpen || isBrowsingThumbnails) return@LaunchedEffect
        delay(CHROME_TIMEOUT_MILLIS)
        isChromeVisible = false
    }

    // The pager owns its position and the model follows, in one direction only.
    LaunchedEffect(position) { viewModel.warm(modelIndex(position)) }

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
        val total = pages.size
        if (target in 0 until total) {
            scope.launch { paging.goTo(target) }
            return
        }
        // `comic-reader`: turning past the last page reaches an end screen rather
        // than nothing. In right-to-left the last *page* is the first display
        // position, which is why this asks the model index rather than the pager.
        if (modelIndex(paging.current) == total - 1) hasReachedEnd = true
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
    fun Page(display: Int, stitch: ScrollAxis? = null) {
        val index = modelIndex(display)
        val bitmap = viewModel.image(index)
        when {
            bitmap != null -> ZoomablePage(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = pages.getOrNull(index)?.path,
                fit = fit,
                onTap = ::handleTap,
                // In a continuous scroll a page takes the height its own proportions
                // ask for. Fitting each one to the screen instead would put a band of
                // background between every pair, which is the opposite of the
                // "stitched with no gap" `comic-reader` asks for.
                stitch = stitch,
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
                    .tappable(::handleTap),
                contentAlignment = Alignment.Center,
            ) {
                if (viewModel.isUnavailable(index)) {
                    // Said, not blank. `publication-formats` requires an archive to
                    // report what it skipped, and this is where a skipped page is met.
                    Message(stringResource(R.string.reader_page_unavailable))
                } else {
                    DelayedProgressIndicator()
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
                    items(count) { Page(it, stitch = ScrollAxis.VERTICAL) }
                }
            } else {
                LazyRow(state = paging.state, modifier = keyboard) {
                    items(count) { Page(it, stitch = ScrollAxis.HORIZONTAL) }
                }
            }
        }
    }

    if (hasReachedEnd) {
        EndOfPublication(
            title = viewModel.publication.displayTitle,
            next = nextInSeries,
            onOpenNext = onOpenNext,
            onBack = { hasReachedEnd = false },
            onClose = onClose,
        )
        return
    }

    AnimatedVisibility(visible = isChromeVisible, enter = fadeIn(), exit = fadeOut()) {
        Box(Modifier.fillMaxSize()) {
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
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
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
                            scope.launch { paging.goTo(displayIndex(index), animate = false) }
                        },
                        modifier = Modifier.padding(bottom = StoryArcSpace.sm),
                    )
                }
                Surface(
                    color = Color.White.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(percent = 50),
                ) {
                    Text(
                        text = stringResource(
                            R.string.reader_page,
                            modelIndex(paging.current) + 1,
                            count,
                        ),
                        style = MaterialTheme.typography.labelLarge,
                        color = Color.White,
                        modifier = Modifier.padding(
                            horizontal = StoryArcSpace.md,
                            vertical = StoryArcSpace.xs,
                        ),
                    )
                }

                if (count > 1) {
                    // Bound to the *publication's* page number, not the pager's
                    // position. In right-to-left the two run opposite ways, and a
                    // slider whose left end is the last page would be a puzzle.
                    // Thumbnails on the slider are the rest of what `comic-reader`
                    // asks for and are not here yet.
                    Slider(
                        value = modelIndex(paging.current).toFloat(),
                        onValueChange = { value ->
                            scope.launch {
                                paging.goTo(displayIndex(value.roundToInt()), animate = false)
                            }
                        },
                        valueRange = 0f..(count - 1).toFloat(),
                        steps = (count - 2).coerceAtLeast(0),
                        colors = SliderDefaults.colors(
                            thumbColor = Color.White,
                            activeTrackColor = Color.White,
                            inactiveTrackColor = Color.White.copy(alpha = 0.3f),
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
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
    contentDescription: String?,
    fit: PageFit,
    onTap: (Offset, IntSize) -> Unit,
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
    var size by remember { mutableStateOf(IntSize.Zero) }
    val page = remember(bitmap, size) {
        PageBounds.of(IntSize(bitmap.width, bitmap.height), size)
    }

    // Back to the fit whenever the page or the mode changes. `comic-reader` wants
    // the *zoom* carried across a turn in fit-to-width mode, and that is what
    // carrying the mode does — the next page opens at its own top, magnified the
    // same way, rather than at whatever corner of the last page was on screen.
    var zoom by remember(bitmap, fit, size) { mutableStateOf(PageZoom.fitting(fit, page)) }

    val transform = rememberTransformableState { centroid, zoomChange, panChange, _ ->
        zoom = zoom.pinched(centroid, zoomChange, panChange, page)
    }

    if (stitch != null) {
        Image(
            bitmap = bitmap,
            contentDescription = contentDescription,
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
            }.tappable(onTap = onTap),
        )
        return
    }

    Image(
        bitmap = bitmap,
        contentDescription = contentDescription,
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

/** Opens and closes the page strip. */
@Composable
private fun ThumbnailToggle(
    isOpen: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onToggle, modifier = modifier.padding(StoryArcSpace.md)) {
        Surface(color = Color.White.copy(alpha = 0.2f), shape = CircleShape) {
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
            Surface(color = Color.White.copy(alpha = 0.2f), shape = CircleShape) {
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
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    LaunchedEffect(open) { onOpenChange(open) }

    Box(modifier) {
        IconButton(onClick = { open = true }, modifier = Modifier.padding(StoryArcSpace.md)) {
            Surface(color = Color.White.copy(alpha = 0.2f), shape = CircleShape) {
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
    next: Publication?,
    onOpenNext: (Publication) -> Unit,
    onBack: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.92f))
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
            Button(onClick = { onOpenNext(next) }) {
                Text(stringResource(R.string.reader_end_next, next.displayTitle))
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
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

private const val FADE_MILLIS = 140

private const val CHROME_TIMEOUT_MILLIS = 4_000L

private const val SPINNER_DELAY_MILLIS = 400L
