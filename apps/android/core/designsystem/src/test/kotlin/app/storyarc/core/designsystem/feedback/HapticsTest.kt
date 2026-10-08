package app.storyarc.core.designsystem.feedback

import android.content.Context
import android.view.HapticFeedbackConstants
import android.view.View
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The app's haptic vocabulary, which is the platform's own.
 *
 * `native-experience` lists haptics among the system affordances the app must use rather than
 * invent. `Haptics.kt` says the same thing in its own words — "`HapticFeedbackConstants`,
 * never a `Vibrator` pattern: these are the effects the device tunes for its own actuator, and
 * they are silent when the reader has turned touch feedback off" — and nothing asserted it. A
 * hand-rolled buzz would be neither tuned nor silent, and it would compile.
 *
 * The view records rather than mocks, so what is asserted is the integer that reaches
 * `View.performHapticFeedback`: the platform's call, carrying the platform's constant. Whether
 * a wrist was actually tapped is a thing only a device can answer, and no device answered it.
 *
 * iOS's `HapticsTests` puts the same two questions to `SensoryFeedback`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HapticsTest {

    /** A view that keeps what it was asked to play instead of asking an actuator. */
    private class RecordingView(context: Context) : View(context) {
        val played = mutableListOf<Int>()

        override fun performHapticFeedback(feedbackConstant: Int): Boolean {
            played += feedbackConstant
            return true
        }
    }

    private fun recorder() = RecordingView(RuntimeEnvironment.getApplication())

    @Test
    fun `a finished thing plays the platform's own confirmation`() {
        val view = recorder()

        Haptics(view).play(StoryArcFeedback.COMPLETION)

        assertEquals(listOf(HapticFeedbackConstants.CONFIRM), view.played)
    }

    @Test
    fun `a request the app cannot honour plays the platform's own rejection`() {
        val view = recorder()

        Haptics(view).play(StoryArcFeedback.REFUSAL)

        assertEquals(listOf(HapticFeedbackConstants.REJECT), view.played)
    }

    @Test
    fun `a new letter under the finger plays the platform's own tick`() {
        val view = recorder()

        Haptics(view).play(StoryArcFeedback.SELECTION)

        assertEquals(listOf(HapticFeedbackConstants.TEXT_HANDLE_MOVE), view.played)
    }

    /**
     * And no two moments in the vocabulary feel the same.
     *
     * Stated over the whole enum rather than over the two words that exist, so a third added
     * later is held to the rule without this file being edited. A vocabulary that has
     * collapsed still plays a haptic at every moment, which is why neither assertion above
     * catches it on its own.
     */
    @Test
    fun `no two moments feel the same`() {
        val played = StoryArcFeedback.entries.map { feedback ->
            val view = recorder()
            Haptics(view).play(feedback)
            assertEquals("$feedback plays nothing, or plays more than once", 1, view.played.size)
            view.played.single()
        }

        assertEquals(
            "two moments in the vocabulary play the same effect: $played",
            played.size,
            played.toSet().size,
        )
    }
}
