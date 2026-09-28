package app.storyarc.feature.epubreader

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `native-experience`: level one had no close control of its own — a swipe or a tap on the
 * scrim closed it, but nothing drawn inside the sheet did, unlike level two's own `TopAppBar`
 * navigation icon (`ThemeAxesScreen`). iOS carries a `Done` button for the same reason
 * (`ThemeSheet.swift`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h1600dp")
class ThemeSheetCloseTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the header's close control dismisses the sheet`() {
        var dismissed = 0

        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ThemeSheet(
                    theme = ReadingTheme(ThemePreset.PAPER),
                    values = ThemePreset.PAPER.values,
                    onAdopt = {},
                    onAdoptColours = { true },
                    onCustomise = {},
                    onDismiss = { dismissed++ },
                )
            }
        }

        compose.onNodeWithContentDescription("Close").performClick()

        assertEquals(
            "The header's close control drew but did not call onDismiss.",
            1,
            dismissed,
        )
    }

    @Test
    fun `with no onDismiss, the header draws no close control`() {
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ThemeSheet(
                    theme = ReadingTheme(ThemePreset.PAPER),
                    values = ThemePreset.PAPER.values,
                    onAdopt = {},
                    onAdoptColours = { true },
                    onCustomise = {},
                )
            }
        }

        compose.onAllNodes(hasContentDescription("Close")).assertCountEquals(0)
    }
}
