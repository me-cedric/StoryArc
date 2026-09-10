package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.IntSize
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
    /** Called once a forward turn has completed. */
    onTurned: () -> Unit,
    /** Called once a backwards turn has completed. */
    onTurnedBack: () -> Unit,
    /** A press that was not a drag: the caller decides what it means. */
    onTap: (Offset, IntSize) -> Unit,
    modifier: Modifier = Modifier,
) {
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    // Off unless `adb` armed it. See `FrameProbe`.
    val frames = remember(view) { FrameTicker(view) }
    // A turn the reader walked out of never reaches `ended`, and a ticker nobody stopped
    // posts a frame callback for the life of the process. This is where it is stopped.
    DisposableEffect(frames) { onDispose { frames.cancel() } }

    Canvas(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(page, beneath, previous, isRightToLeft) {
                awaitEachGesture {
                    val down = awaitFirstDown()

                    var travelled = 0f
                    var lastStep = 0f
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

                        lastStep = change.positionChange().x
                        travelled += lastStep
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
                            frames.began()
                        }

                        change.consume()
                        reached = CurlTurn.progress(
                            base = base,
                            travel = travelled,
                            width = size.width.toFloat(),
                            isRightToLeft = isRightToLeft,
                            canTurnBack = previous != null,
                        )
                        scope.launch { progress.snapTo(reached) }
                    }

                    if (!isDrag) {
                        onTap(down.position, IntSize(size.width, size.height))
                        return@awaitEachGesture
                    }

                    // Directional, unlike the distance: a fast finger dragging the page
                    // back has said it does not want the turn, and an unsigned flick
                    // completed it anyway.
                    val flick = CurlTurn.flicks(lastStep, reached, isRightToLeft)
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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@Canvas
        val sheets = CurlTurn.sheets(progress.value, page, beneath, previous)
        val turning = sheets.turning ?: return@Canvas
        // The matte first, because the shader leaves the letterbox transparent rather than
        // smearing the page's edge pixel across it.
        drawRect(color = matte, size = size)
        drawRect(
            brush = ShaderBrush(
                PageCurl.shader(
                    area = Size(size.width, size.height),
                    progress = sheets.progress,
                    isRightToLeft = isRightToLeft,
                    page = turning,
                    beneath = sheets.under,
                ),
            ),
            size = size,
        )
    }
}

/**
 * How fast a finger has to be leaving the screen, forwards, for the turn to complete
 * anyway.
 *
 * Pixels of travel in the last event, which is a crude velocity and an adequate one:
 * the question is only "was this a flick", and a flick is unmistakable. Measured in
 * turn-space rather than as a distance, so a flick that is dragging the page *back*
 * is not read as one asking it to turn.
 */
private const val FLICK_PIXELS = 12f

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
     */
    fun progress(
        base: Float,
        travel: Float,
        width: Float,
        isRightToLeft: Boolean,
        canTurnBack: Boolean = true,
    ): Float {
        val floor = if (canTurnBack) -1f else 0f
        if (width <= 0f) return base.coerceIn(floor, 1f)
        return (base + forward(travel, isRightToLeft) / width).coerceIn(floor, 1f)
    }

    /**
     * Whether the finger left fast, in the direction the page is already going.
     *
     * Signed, and it has to be: a fast finger dragging a half-turned page *back* has said
     * it does not want the turn, and a fast finger dragging the page behind into view has
     * asked for that one. An unsigned flick answered both with "complete the forward turn".
     */
    fun flicks(lastStep: Float, progress: Float, isRightToLeft: Boolean): Boolean {
        val speed = forward(lastStep, isRightToLeft)
        return if (progress < 0f) speed < -FLICK_PIXELS else speed > FLICK_PIXELS
    }

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
