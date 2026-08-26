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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
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
 * `Animatable` holds a value *and* whatever animation is running on it, and `stop`
 * during a running spring leaves the value where it stands instead of queueing behind
 * it. Interruption is then the default rather than a special case.
 */
@Composable
internal fun CurledPages(
    /** The page being turned away. */
    page: Bitmap?,
    /** The page underneath it, or null at the last page. */
    beneath: Bitmap?,
    isRightToLeft: Boolean,
    /** What shows behind and beside the page. See `matteColour`. */
    matte: Color,
    /** Called once a turn has completed. */
    onTurned: () -> Unit,
    /** A press that was not a drag: the caller decides what it means. */
    onTap: (Offset, IntSize) -> Unit,
    modifier: Modifier = Modifier,
) {
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()

    Canvas(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(page, beneath, isRightToLeft) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    // Taking over rather than waiting: a settle still running is
                    // stopped where it stands, which is what makes a second drag feel
                    // like it continues the first.
                    scope.launch { progress.stop() }

                    var travelled = 0f
                    var lastStep = 0f
                    var isDrag = false
                    // Kept here rather than read back from the `Animatable`. Driving it
                    // means launching a coroutine per move event, and those had not run
                    // by the time the finger lifted — so the release decision read a
                    // progress of zero and sprang every turn back.
                    var reached = 0f

                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break

                        lastStep = change.positionChange().x
                        travelled += lastStep
                        if (abs(travelled) > viewConfiguration.touchSlop) isDrag = true
                        if (!isDrag) continue

                        change.consume()
                        // Turn-space: a right-to-left publication turns forward when
                        // the finger moves the other way, so one sign carries the
                        // whole mirroring.
                        val forward = if (isRightToLeft) travelled else -travelled
                        reached = (forward / size.width).coerceIn(0f, 1f)
                        scope.launch { progress.snapTo(reached) }
                    }

                    if (!isDrag) {
                        onTap(down.position, IntSize(size.width, size.height))
                        return@awaitEachGesture
                    }

                    // Past halfway it completes; before it, it springs back. A flick
                    // completes whatever the distance, because a fast finger has
                    // already said what it meant.
                    val flick = abs(lastStep) > FLICK_PIXELS
                    val settled = reached > 0.5f || (flick && reached > 0.05f)
                    scope.launch {
                        progress.animateTo(if (settled) 1f else 0f, spring())
                        if (settled) {
                            // The page swap first, then the reset: the other order shows
                            // the outgoing page flat for a frame before it goes.
                            onTurned()
                            progress.snapTo(0f)
                        }
                    }
                }
            },
    ) {
        val current = page ?: return@Canvas
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@Canvas
        // The matte first, because the shader leaves the letterbox transparent rather than
        // smearing the page's edge pixel across it.
        drawRect(color = matte, size = size)
        drawRect(
            brush = ShaderBrush(
                PageCurl.shader(
                    area = Size(size.width, size.height),
                    progress = progress.value,
                    isRightToLeft = isRightToLeft,
                    page = current,
                    beneath = beneath,
                ),
            ),
            size = size,
        )
    }
}

/**
 * How fast a finger has to be leaving the screen for the turn to complete anyway.
 *
 * Pixels of travel in the last event, which is a crude velocity and an adequate one:
 * the question is only "was this a flick", and a flick is unmistakable.
 */
private const val FLICK_PIXELS = 12f
