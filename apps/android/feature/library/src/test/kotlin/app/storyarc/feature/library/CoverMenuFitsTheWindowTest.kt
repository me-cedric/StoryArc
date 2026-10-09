package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.isPopup
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `close-the-audited-gaps` 25.3: the cover menu of a chosen cover reached the right edge of the
 * window and its corner was cut. The cover sits at 145 to 266 dp in a 411 dp window, which is
 * where the frame had it, and Material's 280 dp menu fitted neither from its start nor ending
 * at its end.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CoverMenuFitsTheWindowTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a menu that fits neither way is narrowed to fit on the roomier side`() {
        val width = coverMenuMaxWidth(window = 411.dp, anchorLeft = 145.dp, anchorRight = 266.dp)

        assertEquals(250.dp, width)
        assertTrue(145.dp + width + StoryArcSpace.lg <= 411.dp)
    }

    @Test
    fun `a window with room keeps Material's own width`() {
        assertEquals(280.dp, coverMenuMaxWidth(window = 900.dp, anchorLeft = 100.dp, anchorRight = 340.dp))
    }

    @Test
    fun `the open menu is drawn at the width the host worked out`() {
        compose.setContent {
            StoryArcTheme {
                Box(Modifier.fillMaxHeight().padding(start = 145.dp)) {
                    CoverActionsHost(
                        menu = CoverMenu(onChoose = {}, onFind = {}, onWeb = {}, onRemove = {}),
                        open = true,
                        onOpenChange = {},
                        accent = null,
                        modifier = Modifier.width(121.dp),
                    ) { Box(Modifier.width(121.dp).fillMaxHeight(0.4f)) }
                }
            }
        }
        compose.waitForIdle()

        val bounds = compose.onNode(isPopup()).getUnclippedBoundsInRoot()
        assertEquals(coverMenuMaxWidth(411.dp, 145.dp, 266.dp), bounds.right - bounds.left)
    }
}
