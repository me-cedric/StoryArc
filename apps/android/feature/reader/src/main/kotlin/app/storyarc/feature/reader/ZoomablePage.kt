package app.storyarc.feature.reader

import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.LocalTapTurnsPages
import app.storyarc.core.designsystem.theme.swatch
import app.storyarc.core.format.PdfTextPoint
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.ScrollAxis
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

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
internal fun ZoomablePage(
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
    /** D6: what the reader pinched to on the last page, offered to this one. */
    carriedZoomScale: Float?,
    isRightToLeft: Boolean,
    adjustments: ImageAdjustments,
    onTap: (Offset, IntSize) -> Unit,
    /**
     * How far the reader has magnified the page, reported once a pinch settles.
     *
     * `publication-formats` asks for a page to be "re-decoded at higher resolution when
     * the user zooms", and this composable is the only thing that knows how far. Sent
     * after the scale has held still rather than on every frame: a pinch produces dozens
     * of changes a second, and a full-page decode per frame would be the opposite of
     * making the page feel sharp. `overFit` is the same scale as a multiple of the
     * chosen fit's own, which is what fit-to-width carries to the next page (D6).
     */
    onZoom: suspend (scale: Float, overFit: Float) -> Unit,
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
    /**
     * The marks and the live selection to paint over a PDF page, normalised to it.
     *
     * Empty for a comic and for a PDF with no text layer, which is what makes the whole
     * selection apparatus cost a scanned publication nothing.
     */
    decoration: PdfPageDecoration = PdfPageDecoration(),
    /**
     * A press and drag over the text, reported in normalised page coordinates, with `true` once
     * the finger has lifted.
     *
     * Null where there is no text to select, which is also what stops the detector being
     * installed at all -- a gesture that could only ever fail is a gesture that eats presses.
     */
    onSelect: ((PdfTextPoint, PdfTextPoint, Boolean) -> Unit)? = null,
) {
    // Rebuilt only when the reader moves a control, not on every frame of a scroll.
    val colours = remember(adjustments) { adjustments.colourFilter() }
    val sharpen = remember(adjustments) { adjustments.sharpeningEffect() }

    var size by remember { mutableStateOf(IntSize.Zero) }
    val page = remember(bitmap, size) {
        PageBounds.of(IntSize(bitmap.width, bitmap.height), size)
    }
    // The live selection is drawn in the app's own accent rather than in a highlight colour: it
    // is not a mark yet, and colouring it yellow would say that it was.
    val selectionTint = LocalStoryArcPalette.current.accent

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
    var zoom by remember(pageId, fit, size) {
        mutableStateOf(PageZoom.carrying(fit, page, carriedZoomScale, isRightToLeft))
    }

    val transform = rememberTransformableState { centroid, zoomChange, panChange, _ ->
        zoom = zoom.pinched(centroid, zoomChange, panChange, page)
    }
    // D33: in Curl, where a turn starts from. Read while a turn is drawn, not per frame here.
    val curlFrame = LocalCurlFrame.current
    SideEffect { curlFrame?.read = { zoom.frame(page) } }

    // The debounce, and the whole of it: keying the effect on the scale cancels the
    // pending decode every time the pinch moves, so only the magnification the reader
    // stopped at is ever asked for. iOS gets the same restraint from UIKit, which
    // reports `scrollViewDidEndZooming` once at the end of the gesture.
    LaunchedEffect(pageId, zoom.scale) {
        delay(ZOOM_SETTLE_MILLIS)
        onZoom(zoom.scale, zoom.scale / PageZoom.fitting(fit, page).scale)
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
            .transformable(state = transform, canPan = { zoom.claimsPan(it, page) })
            // Centred on what was tapped, not on the middle of the screen: the
            // point of a double-tap is to magnify *that* panel.
            .tappable(
                onTap = onTap,
                onDoubleTap = { zoom = zoom.doubleTapped(it, page, fit) },
                turns = LocalTapTurnsPages.current,
            )
            .selectable(onSelect, zoom, page)
            .graphicsLayer {
                scaleX = zoom.scale
                scaleY = zoom.scale
                translationX = zoom.offset.x
                translationY = zoom.offset.y
                renderEffect = sharpen
            }
            // Inside the layer, so a mark stays on its words through a pinch and a pan.
            // Outside it the highlight would sit still while the page moved underneath.
            .drawWithContent {
                drawContent()
                if (decoration.isEmpty) return@drawWithContent
                for (mark in decoration.marks) {
                    drawRect(
                        color = mark.colour.swatch.copy(alpha = MARK_OPACITY),
                        topLeft = viewRect(mark.rect, page).topLeft,
                        size = viewRect(mark.rect, page).size,
                    )
                }
                for (rect in decoration.selection) {
                    drawRect(
                        color = selectionTint.copy(alpha = SELECTION_OPACITY),
                        topLeft = viewRect(rect, page).topLeft,
                        size = viewRect(rect, page).size,
                    )
                }
            },
    )
}

/**
 * The press that starts a selection, installed only where there is text under the finger.
 *
 * `ebook-reader` requires a text-dependent control to be absent rather than present and inert,
 * and a detector is a control: one that could never resolve would still swallow a long press the
 * page has other plans for.
 *
 * Every point is unprojected before it is normalised. A finger reports where it is on the
 * *screen*, and the words it is over are at a fixed place on the *page* -- the two are the same
 * only at fit scale with nothing panned, which is the one state a reader who has zoomed in to
 * read is not in.
 */
private fun Modifier.selectable(
    onSelect: ((PdfTextPoint, PdfTextPoint, Boolean) -> Unit)?,
    zoom: PageZoom,
    page: PageBounds,
): Modifier {
    if (onSelect == null) return this
    return this.pointerInput(onSelect, zoom, page) {
        var origin = PdfTextPoint(0f, 0f)
        var latest = origin
        detectDragGesturesAfterLongPress(
            onDragStart = {
                origin = normalisedPoint(zoom.unprojected(it, page), page)
                latest = origin
                onSelect(origin, origin, false)
            },
            onDrag = { change, _ ->
                latest = normalisedPoint(zoom.unprojected(change.position, page), page)
                onSelect(origin, latest, false)
            },
            onDragEnd = { onSelect(origin, latest, true) },
            onDragCancel = { onSelect(origin, latest, true) },
        )
    }
}

/** How much of the ink shows. Enough to read as a mark, little enough to read the words under it. */
private const val MARK_OPACITY = 0.38f

/**
 * The live selection is drawn in a neutral tint rather than in a highlight colour: it is not a
 * mark yet, and colouring it yellow would say that it was.
 */
private const val SELECTION_OPACITY = 0.32f

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
internal fun Modifier.tappable(
    onTap: (Offset, IntSize) -> Unit,
    onDoubleTap: ((Offset) -> Unit)? = null,
    /** Whether an edge tap turns a page, and so cannot be the first half of a double-tap. */
    turns: Boolean = true,
): Modifier = this.pointerInput(onTap, onDoubleTap, turns) {
    awaitEachGesture {
        awaitFirstDown()
        val up = waitForUpOrCancellation() ?: return@awaitEachGesture
        val point = up.position

        if (onDoubleTap == null || isEdgeTap(point, size, turns)) {
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

/**
 * Whether a press landed where a turn would happen.
 *
 * Used to decide whether a press should be held waiting for a second tap. With the zones
 * off there is no turn to protect, so no tap is an edge tap and every one is free to
 * become a double-tap zoom.
 */
private fun PointerInputScope.isEdgeTap(point: Offset, area: IntSize, turns: Boolean): Boolean {
    if (!turns) return false
    val edge = area.width * EDGE_ZONE_FRACTION
    return point.x < edge || point.x > area.width - edge
}

/**
 * How much of the width each turn zone takes.
 *
 * A third, so the three zones are equal and the middle one is where a thumb lands on a
 * phone held in one hand. It was a quarter, which left half the screen doing nothing but
 * toggling the chrome -- the gesture a reader uses least occupying the part they hit most.
 *
 * `page-transitions`: "each zone is a third of the screen's width, leaving the middle third
 * to the chrome". iOS's `ZoomablePage.edgeZoneFraction` is the same number, and
 * `ReaderTapZonesTest` on each platform is what stops the two drifting.
 */
internal const val EDGE_ZONE_FRACTION = 1f / 3f

/**
 * A tap in one half of a landscape spread, in the coordinates of the whole spread.
 *
 * The halves are equal, so a tap in one is a tap in the same place on a screen twice as
 * wide. Without this the zones would be measured against half the screen and the middle of
 * a spread would turn the page -- a third of a half is a sixth, so two thirds of a spread
 * would turn, which is the opposite of what `page-transitions` asks for.
 *
 * A function of its own, rather than the two lines it replaced inside the composable,
 * because `ReaderTapZonesTest` cannot reach a lambda in a `Row`.
 *
 * @param half 0 for the leading half of the spread as drawn, 1 for the trailing one.
 */
internal fun spreadTap(half: Int, point: Offset, size: IntSize): Pair<Offset, IntSize> =
    Offset(if (half == 0) point.x else point.x + size.width, point.y) to
        IntSize(size.width * 2, size.height)

/**
 * How long a pinch has to hold still before the page behind it is re-decoded.
 *
 * Short enough that a reader who stops to look does not wait for the sharpening, long
 * enough that crossing four magnifications on the way to the one they wanted costs one
 * decode rather than four. iOS needs no equivalent: UIKit reports the end of the gesture
 * rather than every frame of it.
 */
private const val ZOOM_SETTLE_MILLIS = 180L
