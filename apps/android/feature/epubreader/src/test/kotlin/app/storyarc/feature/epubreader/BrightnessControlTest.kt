package app.storyarc.feature.epubreader

import android.content.Context
import android.provider.Settings
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.math.abs

/**
 * `reading-themes`, *Every axis states its value*, applied to brightness: before this, the
 * stated percentage read `brightness ?: 0.5f` while the slider thumb read the device's own
 * level, so they disagreed on any device not already at exactly 50%.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BrightnessControlTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `the system brightness reads as a fraction of the device's own setting`() {
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 191)

        assertEquals(
            "191 of 255 did not come back as roughly 0.75. The stated percentage and the" +
                " thumb both read this function, so a wrong fraction here is a wrong value" +
                " on both.",
            0.749,
            systemBrightnessFraction(context.contentResolver).toDouble(),
            0.01,
        )
    }

    @Test
    fun `the visible value, the spoken value and the thumb state the device level`() {
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 191)

        compose.setContent {
            StoryArcTheme { BrightnessControl(brightness = null, onChange = {}) }
        }

        compose.onNodeWithText("75%").assertExists(
            "No visible value beside the brightness slider, or it does not state the device" +
                " level. `reading-themes`: \"its current value is stated beside it\".",
        )
        compose.onNodeWithContentDescription("Brightness")
            .assert(
                SemanticsMatcher("states 75% and puts the thumb at 0.75") { node ->
                    val state = node.config.getOrNull(SemanticsProperties.StateDescription)
                    val range = node.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo)
                    state == "75%" && range != null && abs(range.current - 0.749f) < 0.01f
                },
            )
    }
}
