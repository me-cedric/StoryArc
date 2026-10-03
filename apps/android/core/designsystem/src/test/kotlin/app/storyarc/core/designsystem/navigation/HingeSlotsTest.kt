package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `native-experience`, *Foldables*: [HingeSpread] and [HingeInsetPage] place real pages around a
 * hinge. [HingeAvoidanceTest] holds the arithmetic; this asserts the layout the readers draw.
 *
 * Density 1, so one dp is one pixel and a hinge in pixels reads straight off the bounds.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HingeSlotsTest {

    @get:Rule
    val compose = createComposeRule()

    /** [content] in a 300 x 200 px surface. */
    private fun show(content: @Composable () -> Unit) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f)) {
                Box(Modifier.size(300.dp, 200.dp)) { content() }
            }
        }
    }

    private fun bounds(tag: String): Rect = compose.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    private fun assertSpan(tag: String, left: Float, right: Float) {
        val bounds = bounds(tag)
        assertEquals("$tag left", left, bounds.left, 0.5f)
        assertEquals("$tag right", right, bounds.right, 0.5f)
    }

    @Test
    fun `a spread splits at the hinge, with the hinge's own width between the halves`() {
        show { HingeSpread(SurfaceHinge(180f, 190f)) { Box(Modifier.fillMaxSize().testTag("half$it")) } }

        assertSpan("half0", 0f, 180f)
        assertSpan("half1", 190f, 300f)
    }

    @Test
    fun `a spread with no hinge takes two equal halves`() {
        show { HingeSpread(null) { Box(Modifier.fillMaxSize().testTag("half$it")) } }

        assertSpan("half0", 0f, 150f)
        assertSpan("half1", 150f, 300f)
    }

    @Test
    fun `a lone page moves to the wider side of the hinge, at that side's width`() {
        show { HingeInsetPage(SurfaceHinge(100f, 110f)) { Box(Modifier.fillMaxSize().testTag("page")) } }

        assertSpan("page", 110f, 300f)
    }

    @Test
    fun `a lone page with no hinge fills its surface`() {
        show { HingeInsetPage(null) { Box(Modifier.fillMaxSize().testTag("page")) } }

        assertSpan("page", 0f, 300f)
    }

    /** A horizontal strip hands each page an unbounded width. The page keeps its own. */
    @Test
    fun `a page in a horizontal strip keeps its own width`() {
        show {
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                HingeInsetPage(SurfaceHinge(100f, 110f)) { Box(Modifier.size(80.dp).testTag("page")) }
            }
        }

        assertSpan("page", 0f, 80f)
    }
}
