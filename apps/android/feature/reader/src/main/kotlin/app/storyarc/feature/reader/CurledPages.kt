package app.storyarc.feature.reader

import android.graphics.Bitmap
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageCurl
import kotlin.math.abs
import kotlinx.coroutines.launch

/**
 * A page being turned by the finger.
 *
 * `page-transitions` asks for four things that are one loop: the page follows the
 * finger in real time; past halfway the turn completes and before it the page springs
 * back; a flick completes regardless of distance; and a new drag during the settle
 * takes over from where the page is rather than snapping.
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
    /** A press that was not a drag: the caller decides what it means. */
    onTap: (Offset, IntSize) -> Unit,
    /**
     * Where the fold stands: 0 for a flat page, 1 for a whole forward turn, -1 for a whole
     * turn back.
     *
     * Held by [Paging.Curled] rather than here, because a turn asked for by a tap or a key
     * runs the same spring over the same value (task 8.3).
     */
    progress: Animatable<Float, AnimationVector1D>,
    modifier: Modifier = Modifier,
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

    Box(modifier = modifier.fillMaxSize()) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { renderEffect = sharpen }
                .pointerInput(page, beneath, previous, isRightToLeft) {
                    awaitEachGesture {
                        val down = awaitFirstDown()

                        // Frame-rate independent, unlike a raw per-event pixel delta: at 120 Hz
                        // each event carries half the travel it carries at 60 Hz, so a threshold
                        // on the last event's delta missed the same flick on a faster panel.
                        val velocityTracker = VelocityTracker()
                        var travelled = 0f
                        var isDrag = false
                        // Where the page stood when this drag took it over, and where it
                        // stands now. Kept here rather than read back from the `Animatable`
                        // per move: driving it means launching a coroutine per move event,
                        // and those had not run by the time the finger lifted — so the
                        // release decision read a progress of zero and sprang every turn
                        // back.
                        var base = 0f
                        var reached = 0f

                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break

                            velocityTracker.addPointerInputChange(change)
                            travelled += change.positionChange().x
                            if (!isDrag) {
                                if (abs(travelled) <= viewConfiguration.touchSlop) continue
                                isDrag = true
                                // The turn is taken over here rather than at the press: a
                                // settle still running is stopped where it stands, that
                                // value becomes the base the drag is measured from, and the
                                // slop that only proved intent is not also spent turning the
                                // page. A press that never becomes a drag never reaches this,
                                // so a tap during a settle leaves the settle alone.
                                base = progress.value
                                reached = base
                                travelled = 0f
                                scope.launch { progress.stop() }
                                // The turn starts here and ends when its settle completes, so a
                                // count covers the drag and the spring and nothing else.
                                frames.began(isCurl = true)
                            }

                            change.consume()
                            reached = CurlTurn.progress(
                                base = base,
                                travel = travelled,
                                width = size.width.toFloat(),
                                isRightToLeft = isRightToLeft,
                                canTurnBack = previous != null,
                                canTurnForward = beneath != null,
                            )
                            scope.launch { progress.snapTo(reached) }
                        }

                        if (!isDrag) {
                            onTap(down.position, IntSize(size.width, size.height))
                            return@awaitEachGesture
                        }

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
                                if (backwards) onTurnedBack() else onTurned()
                                progress.snapTo(0f)
                            }
                        }
                    }
                },
        ) {
            // The matte first, because the shader leaves the letterbox transparent rather
            // than smearing the page's edge pixel across it — and drawn even when the rest
            // returns early below, so a page still loading is a matte, never a blank hole.
            drawRect(color = matte, size = size)
            // Lint's `NewApi` check reads a version guard, not a null check, however true the
            // two are together: `runtimeShader` is null on exactly this condition, but only
            // this line is what tells the checker `PageCurl.update` below is reachable only
            // at API 33 and above.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@Canvas
            val shader = runtimeShader ?: return@Canvas
            val sheets = CurlTurn.sheets(progress.value, page, beneath, previous)
            val turning = sheets.turning ?: return@Canvas
            PageCurl.update(
                shader,
                width = size.width,
                height = size.height,
                progress = sheets.progress,
                isRightToLeft = isRightToLeft,
                page = turning,
                beneath = sheets.under,
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

/**
 * How fast a finger has to be leaving the screen, forwards, for the turn to complete
 * anyway — in density-independent points per second, in turn-space.
 *
 * Not a raw pixel delta from the last event: that depends on both the display's refresh
 * rate and its density, so the same real flick was missed on a 120 Hz panel (half the
 * travel per event of a 60 Hz one) and read differently on every density. A judgement
 * call rather than a measured one — not measured on a device — but a velocity in
 * physical units is at least the same swipe wherever it runs, which a per-event pixel
 * count is not.
 */
private const val FLICK_DP_PER_SECOND = 800f

/**
 * Where a page stands mid-turn, and what a finger does to it from there.
 *
 * Pulled out of the gesture so it can be tested without a touch screen, the way
 * `TurnDrag` is in the reflowable reader: this is the whole rule, and the rest of
 * [CurledPages] is Compose's pointer contract.
 */
internal object CurlTurn {

    /**
     * Travel in turn-space: positive is towards a completed turn.
     *
     * A right-to-left publication turns forward when the finger moves the other way, so
     * one sign carries the whole mirroring.
     */
    fun forward(travel: Float, isRightToLeft: Boolean): Float =
        if (isRightToLeft) travel else -travel

    /**
     * Where the page stands after [travel] pixels of drag from [base].
     *
     * The base is the whole point. `comic-reader` requires a drag begun during a settle
     * to take over "from the current position without the page snapping", so the drag is
     * an *offset* from where the page stands rather than an absolute reading of the
     * finger: a settle caught at 0.8 and nudged one pixel stays at 0.8, where reading the
     * finger alone would have put it at 0.001.
     *
     * It is also what lets a caught settle be pushed back. Clamping an absolute reading
     * at zero made every backwards move mean "no progress"; clamping base plus travel
     * makes it mean "less progress", which is the same gesture read correctly.
     *
     * @param base the page's progress when the finger took it over, 0 for a flat page.
     * @param travel raw horizontal pixels since the drag was recognised.
     * @param width what a whole turn is measured against. A width nothing has measured
     *   yet leaves the page where it stands rather than dividing by it.
     * @param canTurnBack false at the first page, where a backwards drag moves nothing.
     * @param canTurnForward false at the last page, where there is no sheet beneath. D10:
     *   [PageCurl.update] stands the turning sheet in for a missing one, so the sheet a
     *   lift revealed there was a copy of the sheet being lifted. `page-transitions` puts
     *   both ends under one sentence — "nothing lifts and the page stays where it is,
     *   rather than turning to an empty sheet" — and the end screen is still reached, by
     *   the tap or the key that asked for the turn (`ReaderScreen`'s `turn`).
     */
    fun progress(
        base: Float,
        travel: Float,
        width: Float,
        isRightToLeft: Boolean,
        canTurnBack: Boolean = true,
        canTurnForward: Boolean = true,
    ): Float {
        val floor = if (canTurnBack) -1f else 0f
        val ceiling = if (canTurnForward) 1f else 0f
        if (width <= 0f) return base.coerceIn(floor, ceiling)
        return (base + forward(travel, isRightToLeft) / width).coerceIn(floor, ceiling)
    }

    /**
     * Whether the finger left fast, in the direction the page is already going.
     *
     * Signed, and it has to be: a fast finger dragging a half-turned page *back* has said
     * it does not want the turn, and a fast finger dragging the page behind into view has
     * asked for that one. An unsigned flick answered both with "complete the forward turn".
     *
     * @param velocity dp/s in turn-space — already mirrored for right-to-left by the
     *   caller, through [forward], the same way [progress]'s `travel` is.
     */
    fun flicks(velocity: Float, progress: Float): Boolean =
        if (progress < 0f) velocity < -FLICK_DP_PER_SECOND else velocity > FLICK_DP_PER_SECOND

    /**
     * Which sheet the shader turns, which page lies under it, and at what forward progress.
     *
     * **A backwards turn is the forward projection, run on the page behind.** At a whole
     * turn back the previous page lies flat and fully in view, which is the forward
     * projection at rest; at nothing dragged it is folded entirely away and the current
     * page is what shows, which is the forward projection completed. So `1 + progress`
     * carries the whole of it, and the shader needs no second direction.
     *
     * Generic over the image type so the mapping can be asserted without a bitmap.
     */
    fun <T> sheets(progress: Float, page: T?, beneath: T?, previous: T?): Sheets<T> =
        if (progress < 0f) {
            Sheets(turning = previous, under = page, progress = 1f + progress)
        } else {
            Sheets(turning = page, under = beneath, progress = progress)
        }

    /** What [sheets] decided. */
    data class Sheets<T>(val turning: T?, val under: T?, val progress: Float)

    /**
     * Whether a released turn completes rather than springing back.
     *
     * Past halfway it completes; before it, it springs back. A flick completes whatever
     * the distance, because a fast finger has already said what it meant — and a page
     * that never left flat is not a turn at all, however fast the finger left it.
     */
    fun settles(progress: Float, isFlick: Boolean): Boolean =
        abs(progress) > 0.5f || (isFlick && abs(progress) > 0.05f)
}
