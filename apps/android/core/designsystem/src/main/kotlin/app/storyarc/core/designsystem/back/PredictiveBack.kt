package app.storyarc.core.designsystem.back

import androidx.activity.BackEventCompat
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/**
 * What a screen looks like part-way through a back gesture.
 *
 * A value rather than a set of animation calls, so the shape of the gesture can be
 * asserted by a unit test — the transform is the whole user-visible part of predictive
 * back, and a test that only proved a callback fired would prove nothing about it.
 *
 * @property scale how far the screen has shrunk, 1 at rest.
 * @property originX the edge the shrink is pinned to, in fractions of the width.
 * @property cornerRadius how far the corners have rounded, in dp.
 */
data class BackPreview(
    val scale: Float,
    val originX: Float,
    val cornerRadius: Float,
) {
    /**
     * Whether this frame has to be clipped to its rounded corners.
     *
     * Only while it matters. A clip costs a layer, and a screen at rest would pay it on
     * every frame of every scroll for corners that are not rounded and a shrink that is not
     * happening. Named here rather than written inline in the host's `graphicsLayer`,
     * because a branch inside a composable is a branch no unit test can reach.
     */
    val needsClip: Boolean get() = scale < 1f

    companion object {
        /** A screen nobody is swiping. */
        val settled = BackPreview(scale = 1f, originX = 0.5f, cornerRadius = 0f)

        /** How far the screen shrinks at a fully committed swipe. Android's own 90 %. */
        const val SHRINK = 0.1f

        /** How far the corners round off, in dp, at the same point. */
        const val CORNER = 28f
    }
}

/**
 * The transform for a gesture that has travelled [progress], from the named edge.
 *
 * The screen shrinks away from the finger rather than sliding under it: the origin is
 * pinned to the *opposite* edge, so a swipe from the left opens a gap on the left. That
 * is the movement Android's own back preview makes, and it is what tells a reader the
 * screen is leaving rather than merely being pushed.
 *
 * Clamped rather than trusted. `BackEventCompat.progress` is documented as 0 to 1 and
 * is fed by a finger; a value outside it would otherwise turn the screen inside out.
 */
fun backPreview(progress: Float, fromLeftEdge: Boolean): BackPreview {
    val travelled = progress.coerceIn(0f, 1f)
    return BackPreview(
        scale = 1f - BackPreview.SHRINK * travelled,
        // At rest the origin does not matter — nothing is scaled — so it stays centred
        // and only takes an edge once the gesture has actually moved.
        originX = if (travelled == 0f) 0.5f else if (fromLeftEdge) 1f else 0f,
        cornerRadius = BackPreview.CORNER * travelled,
    )
}

/**
 * The live state of the back gesture, held by the host and written by the handlers.
 *
 * An [Animatable] rather than plain state because the interesting half of the gesture
 * is the half where the reader changes their mind: a cancelled swipe has to settle
 * back, and a snap to rest reads as a glitch.
 */
class BackGestureState internal constructor() {
    internal val travel = Animatable(0f)
    internal var fromLeftEdge by mutableStateOf(true)

    /** The transform to draw right now. */
    val preview: BackPreview get() = backPreview(travel.value, fromLeftEdge)
}

private val LocalBackGesture = staticCompositionLocalOf<BackGestureState?> { null }

/**
 * Wraps the app's screens so a back gesture can preview what leaving looks like.
 *
 * `native-experience` requires "predictive back on Android", and the manifest flag is
 * only the half the system can do for itself: it lets the system draw the way out of
 * the *app*. Everything inside the app is StoryArc's own navigation, so the preview of
 * one of its screens leaving is StoryArc's own to draw.
 *
 * One host around the whole navigation area rather than one per screen. Exactly one
 * screen is composed at a time, so exactly one handler is ever enabled, and a single
 * transform is both cheaper and impossible to apply twice by accident.
 *
 * **Installed once so far, around `SettingsScreen`** — the three-level navigation area that
 * already owned the app's only two [PredictiveBack] handlers, and that therefore had the
 * callbacks firing with nothing drawn. Nesting a second host higher up is safe rather than
 * a conflict: the composition local is static, so the innermost host owns any handler below
 * it, and each still applies its transform exactly once.
 */
@Composable
fun PredictiveBackHost(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val gesture = remember { BackGestureState() }
    CompositionLocalProvider(LocalBackGesture provides gesture) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .graphicsLayer {
                    val preview = gesture.preview
                    scaleX = preview.scale
                    scaleY = preview.scale
                    transformOrigin = TransformOrigin(preview.originX, 0.5f)
                    shape = RoundedCornerShape(preview.cornerRadius.dp)
                    clip = preview.needsClip
                },
        ) {
            content()
        }
    }
}

/**
 * Back, for one screen, previewed as the finger moves.
 *
 * A drop-in for `BackHandler` — same shape, same call site — and the difference is that
 * this one reports how far the gesture has travelled instead of only that it finished.
 * Without a [PredictiveBackHost] above it the callback still fires and nothing is drawn,
 * which is exactly what `BackHandler` did.
 *
 * @param enabled whether this screen wants back at all. A disabled handler lets the one
 *   below it — or the system — have the gesture.
 */
@Composable
fun PredictiveBack(enabled: Boolean = true, onBack: () -> Unit) {
    val gesture = LocalBackGesture.current
    // The settle runs here rather than inside the handler: a cancelled gesture cancels
    // the coroutine the handler gave us, and a suspending animation started in a
    // cancelled coroutine never draws a frame.
    val settling = rememberCoroutineScope()
    PredictiveBackHandler(enabled) { events ->
        try {
            events.collect { event ->
                gesture?.fromLeftEdge = event.swipeEdge == BackEventCompat.EDGE_LEFT
                gesture?.travel?.snapTo(event.progress)
            }
            // Committed. Rest first, so the screen underneath arrives untransformed
            // rather than inheriting the leaving screen's shrink.
            gesture?.travel?.snapTo(0f)
            onBack()
        } catch (cancellation: CancellationException) {
            // The reader changed their mind. Settle rather than snap, and let the
            // cancellation carry on — swallowing it would leave the coroutine that
            // owns this gesture believing it is still running.
            settling.launch { gesture?.travel?.animateTo(0f, tween(durationMillis = SETTLE_MILLIS)) }
            throw cancellation
        }
    }
}

/** `chromeFade` from the motion tokens: the shortest duration that still reads as motion. */
private const val SETTLE_MILLIS = 220
