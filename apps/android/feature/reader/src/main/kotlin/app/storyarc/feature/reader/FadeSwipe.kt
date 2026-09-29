package app.storyarc.feature.reader

import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp

/**
 * The display step a finished horizontal swipe asks for in Fast fade, or 0 for none.
 *
 * `page-transitions` "Turning the tap zones off": every other trigger still turns pages,
 * swipe included. A finger that moves left asks for the next display position, as it does
 * in Slide's pager. Right-to-left needs no flip here, because its display order is already
 * reversed. iOS's `fadeSwipeStep` is the same rule.
 */
internal fun fadeSwipeStep(travel: Float, threshold: Float): Int = when {
    travel <= -threshold -> 1
    travel >= threshold -> -1
    else -> 0
}

/** How far a swipe travels before it turns the page. */
internal val FADE_SWIPE_THRESHOLD = 48.dp

/**
 * Turns the page on a horizontal swipe, by [fadeSwipeStep].
 *
 * Fast fade has no container, so nothing else brings a swipe. A drag the page itself
 * consumes, such as the pan of a zoomed page, never reaches this.
 */
internal fun Modifier.fadeSwipe(onStep: (Int) -> Unit): Modifier = pointerInput(onStep) {
    var travel = 0f
    detectHorizontalDragGestures(
        onDragStart = { travel = 0f },
        onDragEnd = {
            val step = fadeSwipeStep(travel, FADE_SWIPE_THRESHOLD.toPx())
            if (step != 0) onStep(step)
        },
        onHorizontalDrag = { change, amount ->
            change.consume()
            travel += amount
        },
    )
}
