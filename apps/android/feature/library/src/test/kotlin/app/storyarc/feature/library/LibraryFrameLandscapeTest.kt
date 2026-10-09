package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
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
 * `close-the-audited-gaps` 25.2: the Library in a phone held on its side.
 *
 * The title, the notice, the chips and the status line did not scroll, so the shelf had about
 * 35 dp and the A to Z rail drew one letter. These tests compose the frame and the bar the
 * screen is made of at 800 x 360 dp, with a strip as tall as the real one is, and read what the
 * shelf and the rail are left with.
 */
@OptIn(ExperimentalMaterial3Api::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w800dp-h360dp-land")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LibraryFrameLandscapeTest {

    @get:Rule
    val compose = createComposeRule()

    private val strip = 96.dp
    private val navigationBar = 80.dp
    private val window = 360.dp
    private val alphabet = ('A'..'Z').map { RailEntry(it.toString(), it.toString()) }

    /**
     * The library as the screen builds it: its own bar, a navigation bar's height at the foot, the
     * strip, and a shelf with the rail over it. Only the shelf's rows are stand-ins.
     */
    private fun showLibrary() {
        compose.setContent {
            StoryArcTheme {
                val compact = isCompactHeight(LocalConfiguration.current.screenHeightDp)
                val topBarScroll = if (compact) {
                    TopAppBarDefaults.enterAlwaysScrollBehavior()
                } else {
                    TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
                }
                Scaffold(
                    modifier = Modifier.nestedScroll(topBarScroll.nestedScrollConnection),
                    topBar = {
                        LibraryTopBar(
                            scrollBehavior = topBarScroll,
                            onSelect = null,
                            onOpenShelves = null,
                            onOpenSettings = null,
                            compactHeight = compact,
                        )
                    },
                    bottomBar = { Box(Modifier.fillMaxWidth().height(navigationBar)) },
                ) { insets ->
                    LibraryFrame(compact, Modifier.fillMaxSize().padding(insets)) {
                        header { Box(Modifier.fillMaxWidth().height(strip).testTag("strip")) }
                        Box(Modifier.fillMaxSize().testTag("shelf")) {
                            LazyColumn(Modifier.fillMaxSize().testTag("list")) {
                                items((1..60).toList()) { Text("Row $it", Modifier.height(48.dp)) }
                            }
                            IndexRail(alphabet, onChoose = {}, modifier = Modifier.align(Alignment.CenterEnd))
                        }
                    }
                }
            }
        }
    }

    private fun shelfHeight(): Dp = compose.onNodeWithTag("shelf").fetchHeight()

    private fun SemanticsNodeInteraction.fetchHeight(): Dp =
        with(compose.density) { fetchSemanticsNode().size.height.toDp() }

    private val aLetter = SemanticsMatcher("a rail letter") { node ->
        node.config.getOrNull(SemanticsProperties.Text)?.firstOrNull()?.text?.matches(Regex("[A-Z]")) == true
    }

    private fun lettersOnTheRail(): Int =
        compose.onAllNodes(aLetter, useUnmergedTree = true).fetchSemanticsNodes().size

    @Test
    fun `at rest the shelf has a third of the window and the rail draws more than first and last`() {
        showLibrary()

        val letters = lettersOnTheRail()
        assertTrue("the shelf is ${shelfHeight()}", shelfHeight() >= window / 3)
        assertTrue("the rail drew $letters letter(s)", letters > 2)
    }

    @Test
    fun `scrolling the shelf takes the strip and the bar off, and the shelf has most of the window`() {
        showLibrary()
        val atRest = shelfHeight()

        compose.onNodeWithTag("list").performTouchInput { swipeUp() }
        compose.waitForIdle()

        val scrolled = shelfHeight()
        assertTrue("the shelf went from $atRest to $scrolled", scrolled >= atRest + strip)
        assertTrue("the shelf has $scrolled of $window", scrolled >= window * 0.7f)
        assertTrue("the rail drew ${lettersOnTheRail()}", lettersOnTheRail() >= 8)
    }

    @Test
    fun `a window tall enough keeps its strip where it was`() {
        compose.setContent {
            StoryArcTheme {
                LibraryFrame(compactHeight = false, modifier = Modifier.fillMaxSize()) {
                    header { Box(Modifier.fillMaxWidth().height(strip)) }
                    Box(Modifier.fillMaxSize().testTag("shelf")) {
                        LazyColumn(Modifier.fillMaxSize().testTag("list")) {
                            items((1..60).toList()) { Text("Row $it", Modifier.height(48.dp)) }
                        }
                    }
                }
            }
        }
        compose.onNodeWithTag("list").performTouchInput { swipeUp() }
        compose.waitForIdle()

        assertEquals(window - strip, shelfHeight())
    }

    @Test
    fun `the bar is the small one under 480 dp and the medium one above`() {
        var compact by mutableStateOf(true)
        compose.setContent {
            StoryArcTheme {
                Box(Modifier.testTag("bar")) {
                    LibraryTopBar(
                        scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(),
                        onSelect = null,
                        onOpenShelves = null,
                        onOpenSettings = null,
                        compactHeight = compact,
                    )
                }
            }
        }
        val small = compose.onNodeWithTag("bar").fetchHeight()
        compact = false
        compose.waitForIdle()
        val medium = compose.onNodeWithTag("bar").fetchHeight()

        assertTrue("the small bar is $small", small <= 64.dp)
        assertTrue("the medium bar is $medium", medium > 64.dp)
    }

    @Test
    fun `a phone on its side is a compact height and a tablet is not`() {
        assertTrue(isCompactHeight(360))
        assertTrue(!isCompactHeight(COMPACT_HEIGHT_DP))
        assertTrue(!isCompactHeight(891))
    }
}
