package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Where the compact bar goes on a window wide enough for a rail.
 *
 * `audio-playback` asks the bar to rest "above the navigation control" and to "not
 * displace, cover or resize" it. On a phone the navigation control is a row beneath the
 * content and above means above. On a tablet it is a **column beside** the content, and a
 * bar put in the same slot lands on top of the rail — the destinations underneath it — which
 * satisfies the words and breaks the requirement.
 *
 * So on a rail the bar belongs at the foot of the *content* pane: still between the content
 * and the navigation, still taking its own height out of the content rather than covering
 * it, and nowhere near the destinations.
 *
 * A window class the shell answers `showsSidebar` for, which is expanded and above — the
 * same boundary that gives a screen two panes.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37. A tablet window, because the rail is the case.
@Config(sdk = [34], qualifiers = "w1024dp-h800dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CompactPlayerRailTest {

    @get:Rule
    val compose = createComposeRule()

    private val labels = CompactPlayerLabels(play = "Play", pause = "Pause", open = "Open player")

    private val entries = listOf(
        NavigationEntry("Home", Icons.Filled.Home, selected = true) {},
        NavigationEntry("Search", Icons.Filled.Search, selected = false) {},
        NavigationEntry("Settings", Icons.Filled.Settings, selected = false) {},
    )

    @Composable
    private fun Shell() {
        StoryArcTheme {
            AdaptiveNavigationShell(
                entries = entries,
                menu = RailMenuLabels("Expand", "Collapse"),
                aboveNavigation = {
                    CompactPlayerBar(
                        title = "Sea Room",
                        chapter = "Chapter Two",
                        isPlaying = true,
                        progress = 0.4f,
                        labels = labels,
                        onToggle = {},
                        onOpen = {},
                        modifier = Modifier.testTag(BAR),
                    )
                },
            ) {
                LazyColumn(modifier = Modifier.fillMaxSize().testTag(CONTENT)) {
                    items(List(ROWS) { it }) { index ->
                        Box(modifier = Modifier.testTag("row-$index")) { Text("Row $index") }
                    }
                }
            }
        }
    }

    /**
     * The defect, measured: the bar over the rail rather than beside it.
     *
     * A bar that starts where the rail starts is a bar on top of the destinations, and this
     * is the one claim a phone-width test cannot make — at that width the two are stacked
     * and the same arrangement is right.
     */
    @Test
    fun `the bar is not over the rail`() {
        compose.setContent { Shell() }

        val bar = compose.onNodeWithTag(BAR).getUnclippedBoundsInRoot()
        val rail = compose.onNodeWithText("Home").getUnclippedBoundsInRoot()

        assertTrue(
            "the bar spans ${bar.left}..${bar.right} and the rail's destination spans" +
                " ${rail.left}..${rail.right}, so the bar is drawn over the rail",
            bar.left >= rail.right - Dp(TOLERANCE),
        )
    }

    @Test
    fun `the bar is at the foot of the content pane`() {
        compose.setContent { Shell() }

        val bar = compose.onNodeWithTag(BAR).getUnclippedBoundsInRoot()
        val content = compose.onNodeWithTag(CONTENT).getUnclippedBoundsInRoot()

        assertTrue(
            "the content ends at ${content.bottom} and the bar begins at ${bar.top}," +
                " so the bar is not beneath the content",
            bar.top >= content.bottom - Dp(TOLERANCE),
        )
        assertTrue(
            "the bar begins at ${bar.left} and the content at ${content.left}," +
                " so it is not aligned with the pane it belongs to",
            bar.left <= content.left + Dp(TOLERANCE),
        )
    }

    private companion object {
        const val BAR = "compact-player-bar"
        const val CONTENT = "content"
        const val ROWS = 40

        /** A dp of slack, for the rounding a density conversion does. */
        const val TOLERANCE = 1f
    }
}
