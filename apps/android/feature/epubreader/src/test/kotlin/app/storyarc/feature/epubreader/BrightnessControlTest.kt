package app.storyarc.feature.epubreader

import android.content.Context
import android.provider.Settings
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

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
    fun `a device that refuses the read states the middle of the range, not a crash`() {
        // Robolectric's Settings provider answers with no exception when the key was
        // never set, which is the same "unknown" case a real device with a locked-down
        // provider would raise `SettingNotFoundException` for.
        val fraction = systemBrightnessFraction(context.contentResolver)

        assertEquals(0.5, fraction.toDouble(), 0.5)
    }

    @Test
    fun `the stated value and the thumb agree before the reader has moved the slider`() {
        Settings.System.putInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
        val stated = systemBrightnessFraction(context.contentResolver)

        compose.setContent {
            StoryArcTheme { BrightnessControl(brightness = null, onChange = {}) }
        }

        val percent = (stated * 100).let { it.toInt() }
        compose.onNodeWithContentDescription("Brightness")
            .assert(
                SemanticsMatcher("states $percent%") { node ->
                    val state = node.config.getOrNull(SemanticsProperties.StateDescription)
                    state?.contains("$percent") == true
                },
            )
    }
}
