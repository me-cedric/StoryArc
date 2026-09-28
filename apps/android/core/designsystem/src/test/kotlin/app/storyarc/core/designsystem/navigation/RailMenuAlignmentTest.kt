package app.storyarc.core.designsystem.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Text
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.DpRect
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The rail's menu button sits on the same axis as the destinations below it.
 *
 * The field report: in landscape the button that opens the side navigation "sits at the far
 * left". Material 3 puts it at the top of the rail, aligned with the destinations, and its own
 * `WideNavigationRail` samples inset the header's button by 24 dp to get there. The rail
 * places its header at its leading edge, so without that inset the button's centre was 24 dp
 * to the side of every destination's centre.
 *
 * A phone held in landscape: wide enough for the rail, not wide enough to open it by default.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w891dp-h411dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RailMenuAlignmentTest {

    @get:Rule
    val compose = createComposeRule()

    private val entries = listOf(
        NavigationEntry("Home", Icons.Filled.Home, selected = true) {},
        NavigationEntry("Search", Icons.Filled.Search, selected = false) {},
        NavigationEntry("Settings", Icons.Filled.Settings, selected = false) {},
    )

    private val DpRect.centreX get() = (left + right) / 2

    @Test
    fun `the collapsed rail's menu button is centred over its destinations`() {
        compose.setContent {
            StoryArcTheme {
                AdaptiveNavigationShell(entries = entries, menu = RailMenuLabels("Expand", "Collapse")) {
                    Text("Shelf")
                }
            }
        }

        val menu = compose.onNodeWithContentDescription("Expand").getUnclippedBoundsInRoot()
        val home = compose.onNodeWithText("Home").getUnclippedBoundsInRoot()

        assertEquals(
            "the menu button's centre is at ${menu.centreX} and Home's at ${home.centreX}",
            home.centreX.value,
            menu.centreX.value,
            TOLERANCE,
        )
    }

    private companion object {
        /** A dp of slack, for the rounding a density conversion does. */
        const val TOLERANCE = 1f
    }
}
