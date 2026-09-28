package app.storyarc.feature.epubreader

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.doubleClick
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.setting
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.values
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A real finger on a real `Slider`: the long press and the double tap must leave the axis on
 * the preset's value after the finger lifts.
 *
 * `Slider` sets its value when a tap is released, not when it is pressed. A reset that runs
 * while the finger is down is therefore overwritten by the release, unless the detector
 * takes the rest of that press away from `Slider`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h640dp")
class AxisResetGestureTest {

    @get:Rule
    val compose = createComposeRule()

    private fun show(): () -> ThemeValues {
        var latest = ThemePreset.CALM.values.setting(ThemeAxis.LINE_SPACING, 2.5)
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                var values by remember { mutableStateOf(latest) }
                AxisSlider(
                    preset = ThemePreset.CALM,
                    axis = ThemeAxis.LINE_SPACING,
                    range = ThemeAxis.LINE_SPACING.sliderRange!!,
                    values = values,
                    onSet = { axis, value ->
                        values = values.setting(axis, value)
                        latest = values
                    },
                )
            }
        }
        return { latest }
    }

    @Test
    fun `a long press on the track leaves the axis on the preset's value after the lift`() {
        val values = show()

        compose.onNodeWithContentDescription("Line spacing").performTouchInput {
            longClick(Offset(width * 0.1f, centerY))
        }
        compose.waitForIdle()

        assertEquals(
            "The long press reset the axis while the finger was down, and the lift then set" +
                " the value under the finger. `reading-themes`: \"that axis returns to its" +
                " preset value\".",
            ThemePreset.CALM.values.lineHeight,
            values().lineHeight,
            1e-9,
        )
    }

    @Test
    fun `a double tap on the track leaves the axis on the preset's value after the lift`() {
        val values = show()

        compose.onNodeWithContentDescription("Line spacing").performTouchInput {
            doubleClick(Offset(width * 0.1f, centerY))
        }
        compose.waitForIdle()

        assertEquals(
            "The double tap reset the axis on the second press, and the second lift then set" +
                " the value under the finger.",
            ThemePreset.CALM.values.lineHeight,
            values().lineHeight,
            1e-9,
        )
    }

    @Test
    fun `a drag along the track still moves the axis`() {
        val values = show()

        compose.onNodeWithContentDescription("Line spacing").performTouchInput {
            swipeLeft(startX = width * 0.9f, endX = width * 0.1f)
        }
        compose.waitForIdle()

        assertTrue(
            "A drag no longer moves the slider. The reset detector must leave a drag to" +
                " `Slider`. The value is ${values().lineHeight}.",
            values().lineHeight < ThemePreset.CALM.values.lineHeight,
        )
    }
}
