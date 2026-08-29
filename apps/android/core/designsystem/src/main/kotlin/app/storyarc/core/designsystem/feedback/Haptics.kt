package app.storyarc.core.designsystem.feedback

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/**
 * The two moments StoryArc taps a reader on the wrist.
 *
 * `native-experience` lists haptics among the system affordances the app has to use.
 * Which is a shorter list than it sounds: a page turn is the commonest thing that
 * happens in this app, and a comic read at speed is two hundred of them — a buzz on
 * each one is a defect, not a feature. So the vocabulary is deliberately two words
 * wide, and both of them are for something a reader would otherwise have to *notice*
 * had happened.
 *
 * Nothing else gets one, on purpose:
 *
 * - **A page turn** has the page itself as its feedback, and repeats forever.
 * - **The chrome appearing** is what the reader just asked for and can see.
 * - **Dragging the page slider** crosses a page a frame; a tick each would be a rattle.
 * - **A long press** already has the platform's own, from `combinedClickable`.
 * - **A switch or a slider** is answered by the control moving.
 */
enum class StoryArcFeedback {
    /** A thing the reader finished. The end of a publication is the only one so far. */
    COMPLETION,

    /** A request the app cannot honour — a page turn back from the first page. */
    REFUSAL,
    ;

    /**
     * The platform's own constant for this.
     *
     * `HapticFeedbackConstants`, never a `Vibrator` pattern: these are the effects the
     * device tunes for its own actuator, and they are silent when the reader has turned
     * touch feedback off. A hand-rolled buzz would be neither.
     */
    internal val constant: Int
        get() = when (this) {
            COMPLETION -> HapticFeedbackConstants.CONFIRM
            REFUSAL -> HapticFeedbackConstants.REJECT
        }
}

/** Plays the app's haptic vocabulary. Obtain one with [rememberHaptics]. */
class Haptics internal constructor(private val view: View) {
    fun play(feedback: StoryArcFeedback) {
        view.performHapticFeedback(feedback.constant)
    }
}

/**
 * The haptics for this composition.
 *
 * Through the view rather than Compose's `LocalHapticFeedback`, because the two
 * constants this app wants — confirm and reject — are the platform's own and reach the
 * actuator whatever Compose's own vocabulary happens to carry this year.
 */
@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    return remember(view) { Haptics(view) }
}
