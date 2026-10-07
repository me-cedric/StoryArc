package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.RectF
import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.CurlTurn
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageCurl
import app.storyarc.core.model.PageRoll
import kotlin.math.abs
import kotlinx.coroutines.launch

/**
 * Where the page body draws the page, for the curl to start a turn from.
 *
 * The body writes [read] each time it composes; the curl calls it when it draws a turn. A
 * plain holder rather than state, because nothing should recompose when a pinch moves: the
 * value is read only while a turn is drawn.
 */
internal class CurlFrame {
    var read: () -> Rect? = { null }
}

/** The curl's [CurlFrame], or null outside Curl. */
internal val LocalCurlFrame = staticCompositionLocalOf<CurlFrame?> { null }

/**
 * A page being turned by the finger.
 *
 * `page-transitions` asks for four things that are one loop: the page follows the
 * finger in real time; past halfway the turn completes and before it the page springs
 * back; a flick completes regardless of distance; and a new drag during the settle
 * takes over from where the page is rather than snapping.
 *
 * **At rest this is the reader's normal page body** (D33, task 8.16): [body], with its fit,
 * its pinch and its PDF marks, exactly as Fast fade draws it. The shader is drawn over the
 * body only while a turn runs. The body answers a finger first: a pan it claims
 * ([PageZoom.claimsPan]) is consumed and never becomes a turn, so a zoomed page pans. A
 * sideways finger it leaves alone is taken here, in the initial pass from then on, so the
 * body neither pans nor taps under a turning sheet.
 *
 * The last one is why `progress` is an [Animatable] rather than a plain state. An
 * `Animatable` holds a value *and* whatever animation is running on it, so where the
 * page stands mid-settle is a number that can be read. Reading it is the whole of the
 * interruption: the running spring is stopped the moment a drag is recognised, its
 * value becomes the base [CurlTurn.progress] measures the drag from, and the finger
 * picks the page up rather than starting it again from flat.
 */
@Composable
internal fun CurledPages(
    /** The page being turned away. */
    page: Bitmap?,
    /** The page underneath it, or null at the last page. */
    beneath: Bitmap?,
    /**
     * The page behind this one, or null at the first page.
     *
     * `page-transitions`: the turn has a direction, and a backwards drag turns this sheet
     * over the page in view. Null is what stops the first page turning backwards.
     */
    previous: Bitmap?,
    isRightToLeft: Boolean,
    /** What shows behind and beside the page. See `matteColour`. */
    matte: Color,
    /**
     * The series' brightness, contrast, inversion, greyscale and sharpness.
     *
     * `comic-reader` "Persisting adjustments": drawn live over the whole turn, the same
     * way [ZoomablePage] draws them — the border trim is baked into `page`, `beneath`
     * and `previous` before this composable ever sees them, by the caller, the same way
     * every other container bakes it.
     */
    adjustments: ImageAdjustments,
    /** Whether the current page turned out to be undecodable, rather than merely not
     * decoded yet. See `Message`. */
    isUnavailable: Boolean,
    /** What the current page turned out to be, when it could not be decoded. */
    codecName: String?,
    /** Called once a forward turn has completed. */
    onTurned: () -> Unit,
    /** Called once a backwards turn has completed. */
    onTurnedBack: () -> Unit,
    /**
     * Where the fold stands: 0 for a flat page, 1 for a whole forward turn, -1 for a whole
     * turn back.
     *
     * Held by [Paging.Curled] rather than here, because a turn asked for by a tap or a key
     * runs the same spring over the same value (task 8.3).
     */
    progress: Animatable<Float, AnimationVector1D>,
    modifier: Modifier = Modifier,
    /**
     * Whether the publication ends after this page, so a forward turn lifts it off the end
     * screen (D10, task 8.5). See [CurlTurn.under].
     */
    endsHere: Boolean = false,
    /**
     * Where the body draws the page now, or null to fit the sheet to the whole area. Read
     * while a turn is drawn, never at rest.
     */
    pageFrame: () -> Rect? = { null },
    /** Where [beneath] and [previous] will open, or null to fit them to the whole area. */
    beneathOpens: (Bitmap, IntSize) -> Rect? = { _, _ -> null },
    previousOpens: (Bitmap, IntSize) -> Rect? = { _, _ -> null },
    /** The end-of-publication screen, drawn under the sheet while the last page lifts. */
    endScreen: @Composable () -> Unit = {},
    /** The reader's page body, drawn at rest and kept under the sheet while a turn runs. */
    body: @Composable () -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    // What a flick is thresholded in: `VelocityTracker` answers px/s, and a px/s number
    // means a different swipe on a phone and on a tablet at the same density-independent
    // speed. Read once per composition, not once a frame.
    val density = LocalDensity.current.density
    // Parsed once for the life of this composable, not once a frame: `RuntimeShader(source)`
    // parses the whole AGSL program, and the draw block used to pay that on every frame of
    // every turn. `null` below the API floor, where the draw block never reaches it either.
    val runtimeShader = remember {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) PageCurl.newShader() else null
    }
    // Past the last page the shader samples this past the fold, and the end screen shows.
    val clear = remember { Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888) }
    // Off unless `adb` armed it, or this device has not yet judged its own curl. See
    // `FrameProbe` and `CurlVerdict`.
    val frames = remember(view) { FrameTicker(view) }
    // A turn the reader walked out of never reaches `ended`, and a ticker nobody stopped
    // posts a frame callback for the life of the process. This is where it is stopped.
    DisposableEffect(frames) { onDispose { frames.cancel() } }
    val colours = remember(adjustments) { adjustments.colourFilter() }
    val sharpen = remember(adjustments) { adjustments.sharpeningEffect() }
    val hasNoSheet by remember(page, beneath, previous) {
        derivedStateOf { CurlTurn.sheets(progress.value, page, beneath, previous).turning == null }
    }
    val under = CurlTurn.under(beneath, endsHere)
    var isDragging by remember { mutableStateOf(false) }
    // Booleans, so the composition reads a flag and not `progress.value`: reading the value
    // here recomposed this whole composable on every frame of every turn.
    val isTurning by remember { derivedStateOf { isDragging || progress.value != 0f } }
    val reveals by remember(under) {
        derivedStateOf { under == CurlTurn.Under.END_SCREEN && progress.value > 0f }
    }
    // Read by the gesture, which outlives any one composition: a neighbour that decodes
    // mid-drag must not restart it.
    val canTurnBack by rememberUpdatedState(previous != null)
    val canTurnForward by rememberUpdatedState(under != CurlTurn.Under.NOTHING)
    val turned by rememberUpdatedState(onTurned)
    val turnedBack by rememberUpdatedState(onTurnedBack)

    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(isRightToLeft) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)

                    // Frame-rate independent, unlike a raw per-event pixel delta: at 120 Hz
                    // each event carries half the travel it carries at 60 Hz, so a threshold
                    // on the last event's delta missed the same flick on a faster panel.
                    val velocityTracker = VelocityTracker()
                    var travelled = Offset.Zero
                    var isDrag = false
                    // Where the page stood when this drag took it over, and where it
                    // stands now. Kept here rather than read back from the `Animatable`
                    // per move: driving it means launching a coroutine per move event,
                    // and those had not run by the time the finger lifted — so the
                    // release decision read a progress of zero and sprang every turn
                    // back.
                    var base = 0f
                    var reached = 0f

                    try {
                        while (true) {
                            // The body answers first until the drag is ours: the main pass
                            // reaches it before this, and a pan it claims arrives consumed.
                            // From then on the initial pass takes the finger before the body.
                            val pass = if (isDrag) PointerEventPass.Initial else PointerEventPass.Main
                            val event = awaitPointerEvent(pass)
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            if (!isDrag && (change.isConsumed || event.changes.count { it.pressed } > 1)) break

                            velocityTracker.addPointerInputChange(change)
                            travelled += change.positionChange()
                            if (!isDrag) {
                                if (abs(travelled.x) <= viewConfiguration.touchSlop) continue
                                // A finger going down a fit-to-width page is a scroll.
                                if (abs(travelled.y) > abs(travelled.x)) break
                                isDrag = true
                                isDragging = true
                                // The turn is taken over here rather than at the press: a
                                // settle still running is stopped where it stands, that
                                // value becomes the base the drag is measured from, and the
                                // slop that only proved intent is not also spent turning the
                                // page. A press that never becomes a drag never reaches this,
                                // so a tap during a settle leaves the settle alone.
                                base = progress.value
                                reached = base
                                travelled = Offset.Zero
                                scope.launch { progress.stop() }
                                // The turn starts here and ends when its settle completes, so a
                                // count covers the drag and the spring and nothing else.
                                frames.began(isCurl = true)
                            }

                            change.consume()
                            reached = CurlTurn.progress(
                                base = base,
                                travel = travelled.x,
                                width = size.width.toFloat(),
                                isRightToLeft = isRightToLeft,
                                canTurnBack = canTurnBack,
                                canTurnForward = canTurnForward,
                            )
                            scope.launch { progress.snapTo(reached) }
                        }
                    } finally {
                        // A gesture cut off mid-drag still lets the body back.
                        isDragging = false
                    }

                    // Taps are the body's, the way every other mode's are.
                    if (!isDrag) return@awaitEachGesture

                    // Directional, unlike the distance: a fast finger dragging the page
                    // back has said it does not want the turn, and an unsigned flick
                    // completed it anyway. Turn-space carries the sign the same way a
                    // drag's travel does, and dp/s is what makes the threshold mean the
                    // same swipe on every density and every refresh rate.
                    val velocityDp = CurlTurn.forward(
                        travel = velocityTracker.calculateVelocity().x,
                        isRightToLeft = isRightToLeft,
                    ) / density
                    val flick = CurlTurn.flicks(velocity = velocityDp, progress = reached)
                    val settled = CurlTurn.settles(progress = reached, isFlick = flick)
                    val backwards = reached < 0f
                    scope.launch {
                        progress.animateTo(
                            targetValue = if (!settled) 0f else if (backwards) -1f else 1f,
                            animationSpec = spring(),
                        )
                        // The turn is over either way — a page that sprang back still spent
                        // frames. A settle a later drag took over never reaches this, and
                        // that drag's own settle closes the count.
                        frames.ended()
                        if (settled) {
                            // The page swap first, then the reset: the other order shows
                            // the outgoing page flat for a frame before it goes.
                            if (backwards) turnedBack() else turned()
                            progress.snapTo(0f)
                        }
                    }
                }
            },
    ) {
        // D10: the end screen is the next sheet past the last page. It sits under the
        // body, which hides while it is revealed and so keeps every touch: nothing on the
        // end screen answers until the turn has landed and the real one is up.
        if (reveals) Box(Modifier.fillMaxSize().clearAndSetSemantics {}) { endScreen() }
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (reveals) 0f else 1f }) { body() }
        if (!isTurning) return@Box
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { renderEffect = sharpen },
        ) {
            // The matte first, because the shader leaves the letterbox transparent rather
            // than smearing the page's edge pixel across it — and drawn even when the rest
            // returns early below, so a page still loading is a matte, never a blank hole.
            // Past the last page it stops at the sheet's rim, so the end screen shows.
            if (reveals) {
                drawPath(sheetPath(size.width, size.height, progress.value, isRightToLeft), matte)
            } else {
                drawRect(color = matte, size = size)
            }
            // Lint's `NewApi` check reads a version guard, not a null check, however true the
            // two are together: `runtimeShader` is null on exactly this condition, but only
            // this line is what tells the checker `PageCurl.update` below is reachable only
            // at API 33 and above.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@Canvas
            val shader = runtimeShader ?: return@Canvas
            val sheets = CurlTurn.sheets(progress.value, page, beneath, previous)
            val turning = sheets.turning ?: return@Canvas
            // The same choice of sheets, made over where each one lies flat: the page where
            // the body draws it, and its neighbours where they will open.
            val area = IntSize(size.width.toInt(), size.height.toInt())
            val lying = CurlTurn.sheets(
                progress.value,
                pageFrame(),
                beneath?.let { beneathOpens(it, area) },
                previous?.let { previousOpens(it, area) },
            )
            PageCurl.update(
                shader,
                width = size.width,
                height = size.height,
                progress = sheets.progress,
                isRightToLeft = isRightToLeft,
                page = turning,
                beneath = if (reveals) clear else sheets.under,
                pageFrame = lying.turning?.toRectF(),
                beneathFrame = lying.under?.toRectF(),
            )
            drawRect(brush = ShaderBrush(shader), size = size, colorFilter = colours)
        }
        // `publication-formats`: a page still loading or that could not be decoded is named
        // rather than left as a bare matte, in Curl as in every other mode. Derived, so the
        // composition reads a boolean and not `progress.value`: reading the value here
        // recomposed this whole composable on every frame of every turn.
        if (hasNoSheet) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (isUnavailable) {
                    Message(
                        if (codecName != null) {
                            stringResource(R.string.reader_page_unavailable_codec, codecName)
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
}

private fun Rect.toRectF() = RectF(left, top, right, bottom)

/** The turning sheet's outline as a path. See [CurlTurn.sheetOutline]. */
private fun sheetPath(width: Float, height: Float, progress: Float, isRightToLeft: Boolean): Path =
    Path().apply {
        val outline = CurlTurn.sheetOutline(width, height, progress, isRightToLeft)
        moveTo(outline.first().x, outline.first().y)
        for (point in outline.drop(1)) lineTo(point.x, point.y)
        close()
    }

/** How many segments approximate the rim, top to foot. See [CurlTurn.sheetOutline]. */
private const val OUTLINE_STEPS = 24

/**
 * The outline of the turning sheet: every point with x at or before the lip's rim.
 *
 * Past the rim the shader draws the page beneath. When that is the end screen the
 * shader leaves it transparent, and the matte has to stop at the same curve, or the
 * end screen shows through only where the matte was not. [PageRoll] is the one model
 * both use, so the curve is the shader's own.
 */
internal fun CurlTurn.sheetOutline(
    width: Float,
    height: Float,
    progress: Float,
    isRightToLeft: Boolean,
    steps: Int = OUTLINE_STEPS,
): List<Offset> {
    val radius = PageRoll.radius(width, progress)
    val count = steps.coerceAtLeast(1)
    val rim = (0..count).map { step ->
        val y = height * step / count
        val x = (PageRoll.fold(width, height, progress, y, radius) + radius).coerceIn(0f, width)
        Offset(if (isRightToLeft) width - x else x, y)
    }
    val spine = if (isRightToLeft) width else 0f
    return listOf(Offset(spine, 0f)) + rim + Offset(spine, height)
}
