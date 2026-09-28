package app.storyarc.feature.epubreader

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.changedToUp

/**
 * A long press or a double tap on the slider itself, either of which resets the axis it
 * belongs to.
 *
 * `reading-themes`, *Resetting an axis*: "a user long-presses or double-taps a slider ...
 * that axis returns to its preset value". `Slider` consumes the first pointer down on the
 * [PointerEventPass.Main] pass for its own drag, which is the pass `detectTapGestures` also
 * reads — so a tap detector wrapped around a `Slider` never starts, because the down it
 * needs has already been consumed by the time its own pass runs. Reading the
 * [PointerEventPass.Initial] pass instead sees every change before `Slider` does. Nothing
 * is consumed until a reset is decided, so a tap or a drag reaches `Slider` unchanged.
 *
 * **After a reset, the rest of that press is consumed.** `Slider` sets its value when a tap
 * is released, not when it is pressed. Without the consumption, the lift after a long press,
 * or after the second tap of a double tap, writes the value under the finger over the reset.
 *
 * The timeout reads are [AwaitPointerEventScope.withTimeoutOrNull], not
 * `kotlinx.coroutines.withTimeoutOrNull`: the pointer input dispatch loop needs its own
 * cancellation so a timeout here cannot leave the gesture coroutine reading a stale event.
 *
 * task `reader-theming-and-page-transitions` 3.5, item 2, and `native-experience` D35 (both
 * gestures, one reset path, `resetAxis`).
 */
internal suspend fun PointerInputScope.detectAxisResetGesture(onReset: () -> Unit) {
    val longPressTimeoutMillis = viewConfiguration.longPressTimeoutMillis
    val doubleTapTimeoutMillis = viewConfiguration.doubleTapTimeoutMillis
    val slop = viewConfiguration.touchSlop

    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)

        when (awaitPressOutcome(down.id, down.position, slop, longPressTimeoutMillis)) {
            PressOutcome.LONG_PRESSED -> {
                onReset()
                consumeUntilUp(down.id)
            }
            PressOutcome.TAPPED_NEARBY -> {
                // The first tap reached `Slider` and moved the thumb. The second down is
                // taken away from `Slider`, so the reset is the last write.
                val secondDown = withTimeoutOrNull(doubleTapTimeoutMillis) {
                    awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                }
                if (secondDown != null) {
                    secondDown.consume()
                    onReset()
                    consumeUntilUp(secondDown.id)
                }
            }
            PressOutcome.MOVED_OR_CANCELED -> Unit
        }
    }
}

private enum class PressOutcome { LONG_PRESSED, TAPPED_NEARBY, MOVED_OR_CANCELED }

/**
 * Waits, on the [PointerEventPass.Initial] pass, for the one pointer this press started
 * with to either travel past [slop] (a drag: [PressOutcome.MOVED_OR_CANCELED]), lift again
 * within [slop] before [longPressTimeoutMillis] (a tap: [PressOutcome.TAPPED_NEARBY]), or
 * still be down and within [slop] when [longPressTimeoutMillis] elapses
 * ([PressOutcome.LONG_PRESSED]).
 */
private suspend fun AwaitPointerEventScope.awaitPressOutcome(
    pointerId: PointerId,
    start: Offset,
    slop: Float,
    longPressTimeoutMillis: Long,
): PressOutcome {
    val outcome = withTimeoutOrNull(longPressTimeoutMillis) {
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            val change = event.changes.firstOrNull { it.id == pointerId }
                ?: return@withTimeoutOrNull PressOutcome.MOVED_OR_CANCELED
            if ((change.position - start).getDistance() > slop) {
                return@withTimeoutOrNull PressOutcome.MOVED_OR_CANCELED
            }
            if (change.changedToUp()) return@withTimeoutOrNull PressOutcome.TAPPED_NEARBY
        }
        @Suppress("UNREACHABLE_CODE")
        PressOutcome.MOVED_OR_CANCELED
    }
    return outcome ?: PressOutcome.LONG_PRESSED
}

private suspend fun AwaitPointerEventScope.consumeUntilUp(pointerId: PointerId) {
    while (true) {
        val event = awaitPointerEvent(PointerEventPass.Initial)
        val change = event.changes.firstOrNull { it.id == pointerId } ?: return
        change.consume()
        if (!change.pressed) return
    }
}
