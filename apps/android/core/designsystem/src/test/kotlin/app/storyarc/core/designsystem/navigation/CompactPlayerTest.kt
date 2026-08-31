package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The compact bar, and what it must not do to the navigation control.
 *
 * `audio-playback`:
 *
 * > **THEN** a compact bar rests above the navigation control, naming the publication and
 * > the chapter being spoken, and offering play, pause and a way to open the full player
 * > **AND** it does not displace, cover or resize the navigation control, and the content
 * > behind it can still be scrolled to its end
 *
 * Every clause after the first is a **layout** claim, and none of them can be answered by
 * asserting that a composable was called — which is exactly how a bar that quietly sits on
 * top of the navigation bar ships. Robolectric with `GraphicsMode.NATIVE`, for the reasons
 * `WhatsNewLayoutTest` sets out at length: legacy graphics measure every glyph at about a
 * pixel wide, and a suite run that way would pass against a bar that clips.
 *
 * iOS's `CompactPlayerTests` asserts the same claims of `tabViewBottomAccessory`.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it. A phone
// window, because the phone is where the bar sits above a navigation *bar*.
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CompactPlayerTest {

    @get:Rule
    val compose = createComposeRule()

    private val labels = CompactPlayerLabels(play = "Play", pause = "Pause", open = "Open player")

    private val entries = listOf(
        NavigationEntry("Home", Icons.Filled.Home, selected = true) {},
        NavigationEntry("Search", Icons.Filled.Search, selected = false) {},
        NavigationEntry("Settings", Icons.Filled.Settings, selected = false) {},
    )

    /**
     * The shell, with the bar in its slot or without it.
     *
     * The whole shell rather than the bar alone, because every claim below is about the
     * *relationship* between the bar and the navigation control, and a bar composed on its
     * own has no relationship to assert.
     */
    @Composable
    private fun Shell(bar: Boolean, fontScale: Float = 1f, chapter: String? = "Chapter Two") {
        val density = LocalDensity.current
        CompositionLocalProvider(
            LocalDensity provides Density(density.density, fontScale),
        ) {
            StoryArcTheme {
                AdaptiveNavigationShell(
                    entries = entries,
                    menu = RailMenuLabels("Expand", "Collapse"),
                    aboveNavigation = {
                        if (bar) {
                            CompactPlayerBar(
                                title = "Sea Room",
                                chapter = chapter,
                                isPlaying = true,
                                progress = 0.4f,
                                labels = labels,
                                onToggle = {},
                                onOpen = {},
                                modifier = Modifier.testTag(BAR),
                            )
                        }
                    },
                ) {
                    LazyColumn(modifier = Modifier.fillMaxSize().testTag(CONTENT)) {
                        items(ROWS) { index ->
                            Box(modifier = Modifier.testTag(row(index))) {
                                Text("Row $index")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    fun `the bar names the publication and the chapter`() {
        compose.setContent { Shell(bar = true) }
        compose.onNodeWithText("Sea Room", useUnmergedTree = true).assertIsDisplayed()
        // The **chapter**, not the file. A product decision, and the one line the bar has
        // room for beside the title.
        compose.onNodeWithText("Chapter Two", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun `the bar is absent when nothing plays and its space returns to the content`() {
        // Both halves of "the compact bar is absent rather than present and empty, and the
        // space it occupied returns to the content". Measured, because a bar drawn with
        // zero alpha would satisfy the first half and fail the second.
        //
        // One composition with the bar switched on inside it, rather than two `setContent`
        // calls: a compose rule refuses the second, and switching is the truer test anyway
        // — it is what happens when a listener presses play.
        val showing = mutableStateOf(false)
        compose.setContent { Shell(bar = showing.value) }

        compose.onNodeWithTag(BAR).assertDoesNotExist()
        val withoutBar = compose.onNodeWithTag(CONTENT).getUnclippedBoundsInRoot().let { it.bottom - it.top }

        showing.value = true
        compose.waitForIdle()
        val withBar = compose.onNodeWithTag(CONTENT).getUnclippedBoundsInRoot().let { it.bottom - it.top }

        assertTrue(
            "the content is $withBar with the bar and $withoutBar without it — the bar" +
                " took no room, so it is drawn over something",
            withBar < withoutBar,
        )
    }

    @Test
    fun `the bar does not displace, cover or resize the navigation control`() {
        // Three claims, one measurement each, and the middle one is the defect this exists
        // for: a bar laid over the navigation bar looks right in a screenshot and eats
        // every tap on the middle destination.
        val showing = mutableStateOf(false)
        compose.setContent { Shell(bar = showing.value) }
        val bare = compose.onNodeWithText("Home").getUnclippedBoundsInRoot()

        showing.value = true
        compose.waitForIdle()
        val withBar = compose.onNodeWithText("Home").getUnclippedBoundsInRoot()
        val bar = compose.onNodeWithTag(BAR).getUnclippedBoundsInRoot()

        // Not resized.
        assertEquals((bare.bottom - bare.top).value, (withBar.bottom - withBar.top).value, TOLERANCE)
        assertEquals((bare.right - bare.left).value, (withBar.right - withBar.left).value, TOLERANCE)
        // Not displaced: the control is still at the foot of the window.
        assertEquals(bare.bottom.value, withBar.bottom.value, TOLERANCE)
        // Not covered: the bar ends where the control begins, at the latest.
        assertTrue(
            "the bar's bottom is ${bar.bottom} and the control's top is ${withBar.top}," +
                " so the bar is over the navigation control",
            bar.bottom <= withBar.top + Dp(TOLERANCE),
        )
    }

    @Test
    fun `the content behind the bar still scrolls to its end`() {
        // The clause a bar drawn as an overlay fails silently: the list scrolls, the last
        // row arrives, and it arrives underneath the bar.
        compose.setContent { Shell(bar = true) }
        compose.onNodeWithTag(CONTENT).performScrollToIndex(ROWS - 1)
        compose.onNodeWithTag(row(ROWS - 1)).assertIsDisplayed()

        val last = compose.onNodeWithTag(row(ROWS - 1)).getUnclippedBoundsInRoot()
        val bar = compose.onNodeWithTag(BAR).getUnclippedBoundsInRoot()
        assertTrue(
            "the last row ends at ${last.bottom} and the bar begins at ${bar.top}," +
                " so the end of the content is under the bar",
            last.bottom <= bar.top + Dp(TOLERANCE),
        )
    }

    @Test
    fun `at the largest text size the bar grows rather than truncating the chapter`() {
        // `audio-playback`: "the compact bar grows to fit its text rather than truncating
        // the chapter to one word". Two lines each and a column with no fixed height is
        // what makes that true; a `Row` with a pinned height is what would not.
        val scale = mutableFloatStateOf(1f)
        compose.setContent { Shell(bar = true, fontScale = scale.floatValue) }
        val normal = compose.onNodeWithTag(BAR).getUnclippedBoundsInRoot().let { it.bottom - it.top }

        scale.floatValue = 2f
        compose.waitForIdle()
        val largest = compose.onNodeWithTag(BAR).getUnclippedBoundsInRoot().let { it.bottom - it.top }

        assertTrue(
            "the bar is $normal at the default text size and $largest at the largest," +
                " so it is pinned and its text has nowhere to go",
            largest > normal,
        )
        compose.onNodeWithText("Chapter Two", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun `a source with no chapter still names the publication`() {
        // A read-aloud session that has not reached a named resource yet, and a folder part
        // with no title. The bar is not empty and the row does not collapse.
        compose.setContent { Shell(bar = true, chapter = null) }
        compose.onNodeWithText("Sea Room", useUnmergedTree = true).assertIsDisplayed()
    }

    private companion object {
        const val BAR = "compact-player-bar"
        const val CONTENT = "content"
        const val ROWS = 40

        /** A dp of slack, for the rounding a density conversion does. */
        const val TOLERANCE = 1f

        fun row(index: Int) = "row-$index"
    }
}
