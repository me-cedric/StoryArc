package app.storyarc.feature.epubreader

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemeValues
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `native-experience`, applied to the font-size stepper: a tap on Larger used to leave
 * TalkBack focus on the button with the new position unannounced, because the merged node
 * carried no live region. `FontSizeControl` moved from `private` to `internal` so this test
 * can reach it directly, the same lift `AGENTS.md` §... describes for a rule a test cannot
 * otherwise reach through the view.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FontSizeControlTest {

    @get:Rule
    val compose = createComposeRule()

    private fun largerButton() = compose.onNode(
        SemanticsMatcher("contentDescription contains Larger") { node ->
            node.config.getOrNull(SemanticsProperties.ContentDescription)
                ?.any { it.contains("Larger") } == true
        },
        useUnmergedTree = true,
    )

    @Test
    fun `the stepper carries a polite live region`() {
        compose.setContent {
            StoryArcTheme {
                FontSizeControl(
                    values = ThemeValues(),
                    onChange = { _, _ -> },
                    modifier = Modifier.testTag("stepper"),
                )
            }
        }

        val liveRegion = compose.onNodeWithTag("stepper")
            .fetchSemanticsNode()
            .config
            .getOrNull(SemanticsProperties.LiveRegion)

        assertEquals(
            "The stepper carries no live region, so TalkBack never re-announces a step made" +
                " from the buttons rather than a swipe adjust.",
            LiveRegionMode.Polite,
            liveRegion,
        )
    }

    @Test
    fun `the stated position changes when the reader taps Larger`() {
        var values by mutableStateOf(ThemeValues(fontSize = FontSizeStep.NORMAL))

        compose.setContent {
            StoryArcTheme {
                FontSizeControl(
                    values = values,
                    onChange = { axis, new -> if (axis == ThemeAxis.FONT_SIZE) values = new },
                    modifier = Modifier.testTag("stepper"),
                )
            }
        }

        val before = compose.onNodeWithTag("stepper")
            .fetchSemanticsNode()
            .config
            .getOrNull(SemanticsProperties.StateDescription)

        largerButton().performClick()
        compose.waitForIdle()

        val after = compose.onNodeWithTag("stepper")
            .fetchSemanticsNode()
            .config
            .getOrNull(SemanticsProperties.StateDescription)

        assertTrue(
            "The stated position did not change after a step, so a live region has nothing" +
                " new to announce even once one is attached. before=$before after=$after",
            before != after,
        )
    }
}
