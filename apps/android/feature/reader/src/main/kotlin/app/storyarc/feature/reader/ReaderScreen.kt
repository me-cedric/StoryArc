package app.storyarc.feature.reader

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PageEntry
import app.storyarc.core.model.ReadingDirection
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
    modifier: Modifier = Modifier,
) {
    val pages by viewModel.pages.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()

    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val maxPixelSize = with(density) {
        maxOf(configuration.screenWidthDp.dp, configuration.screenHeightDp.dp).roundToPx()
    }

    LaunchedEffect(Unit) { viewModel.open(maxPixelSize) }

    // `comic-reader`: "the screen does not auto-lock while a page is visible, and
    // normal locking resumes on leaving". A long look at one page is reading, not
    // idling. On the view rather than the window flag, so leaving the screen
    // restores the device's own behaviour without the reader having to remember to.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    Box(
        // Black behind every page, whatever the app's appearance. A comic is read
        // against its own artwork, not against a themed surface.
        modifier = modifier.fillMaxSize().background(Color.Black),
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
            else -> Pager(viewModel, pages, onClose)
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
private fun Pager(viewModel: ReaderViewModel, pages: List<PageEntry>, onClose: () -> Unit) {
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

    val pagerState = rememberPagerState(
        initialPage = displayIndex(viewModel.initialIndex),
        pageCount = { count },
    )
    val scope = rememberCoroutineScope()

    // `comic-reader`: nothing is on screen while reading, and the chrome fades out
    // again after four seconds of no interaction.
    var isChromeVisible by remember { mutableStateOf(true) }
    LaunchedEffect(isChromeVisible, pagerState.currentPage) {
        if (!isChromeVisible) return@LaunchedEffect
        delay(CHROME_TIMEOUT_MILLIS)
        isChromeVisible = false
    }

    // The pager owns its position and the model follows, in one direction only.
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.currentPage }.collect { page ->
            viewModel.warm(modelIndex(page))
        }
    }

    /**
     * What a tap means, by where it landed.
     *
     * The edges turn pages and do not reveal the chrome; the centre toggles it.
     * The zones are mirrored for right-to-left for free — the pager's *data* is
     * reversed, so one step right on screen is one step right on screen whichever
     * way the story runs.
     */
    fun handleTap(point: Offset, size: IntSize) {
        val edge = size.width * EDGE_ZONE_FRACTION
        val target = when {
            point.x < edge -> pagerState.currentPage - 1
            point.x > size.width - edge -> pagerState.currentPage + 1
            else -> {
                isChromeVisible = !isChromeVisible
                return
            }
        }
        if (target in 0 until count) {
            scope.launch { pagerState.animateScrollToPage(target) }
        }
    }

    // `comic-reader`: the mapped keys turn pages. Arrow, page and space only —
    // volume buttons are behind a setting the app does not have yet.
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    HorizontalPager(
        state = pagerState,
        modifier = Modifier
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
                val target = pagerState.currentPage + step
                if (target in 0 until count) {
                    scope.launch { pagerState.animateScrollToPage(target) }
                }
                true
            },
    ) { page ->
        val index = modelIndex(page)
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val bitmap = viewModel.image(index)
            when {
                bitmap != null -> ZoomablePage(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = pages.getOrNull(index)?.path,
                    onTap = ::handleTap,
                )
                // A page that is not drawn still has to accept a tap: a reader who
                // lands on a skipped page must be able to turn away from it.
                else -> Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .tappable(::handleTap),
                    contentAlignment = Alignment.Center,
                ) {
                    if (viewModel.isUnavailable(index)) {
                        // Said, not blank. `publication-formats` requires an
                        // archive to report what it skipped, and this is where a
                        // skipped page is met.
                        Message(stringResource(R.string.reader_page_unavailable))
                    } else {
                        DelayedProgressIndicator()
                    }
                }
            }
        }
    }

    AnimatedVisibility(visible = isChromeVisible, enter = fadeIn(), exit = fadeOut()) {
        Box(Modifier.fillMaxSize()) {
            CloseButton(onClose)

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = StoryArcSpace.md, vertical = StoryArcSpace.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Surface(
                    color = Color.White.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(percent = 50),
                ) {
                    Text(
                        text = stringResource(
                            R.string.reader_page,
                            modelIndex(pagerState.currentPage) + 1,
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
                        value = modelIndex(pagerState.currentPage).toFloat(),
                        onValueChange = { value ->
                            scope.launch {
                                pagerState.scrollToPage(displayIndex(value.roundToInt()))
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
    onTap: (Offset, IntSize) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Reset per page: a magnified corner of the last page carried onto the next
    // one is disorienting, and `comic-reader`'s "zoom persists across pages" is
    // about fit-to-width mode, which is not built yet.
    var zoom by remember(bitmap) { mutableStateOf(PageZoom()) }
    var size by remember { mutableStateOf(IntSize.Zero) }

    val transform = rememberTransformableState { centroid, zoomChange, panChange, _ ->
        zoom = zoom.pinched(centroid, zoomChange, panChange, size)
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
            .transformable(state = transform, canPan = { zoom.isMagnified })
            // Centred on what was tapped, not on the middle of the screen: the
            // point of a double-tap is to magnify *that* panel.
            .tappable(onTap = onTap, onDoubleTap = { zoom = zoom.doubleTapped(it, size) })
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
private const val EDGE_ZONE_FRACTION = 0.25f

private const val CHROME_TIMEOUT_MILLIS = 4_000L

private const val SPINNER_DELAY_MILLIS = 400L
