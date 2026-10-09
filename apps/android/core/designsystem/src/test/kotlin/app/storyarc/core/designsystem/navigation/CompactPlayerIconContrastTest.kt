package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `close-the-audited-gaps` 25.3: in dark the play triangle on the compact bar was near black on
 * near black. A mark has to clear 3:1 against what it is drawn on.
 *
 * Read off the pixels, because the icon's colour is inherited and no semantics property
 * states it: the colour furthest from the bar's own ground, in the strip the button sits in.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CompactPlayerIconContrastTest {

    @get:Rule
    val compose = createComposeRule()

    private val labels = CompactPlayerLabels(play = "Play", pause = "Pause", open = "Open player")

    private fun luminance(color: Color): Double {
        fun channel(value: Float): Double =
            value.toDouble().let { if (it <= 0.03928) it / 12.92 else Math.pow((it + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    private fun contrast(a: Color, b: Color): Double {
        val one = luminance(a)
        val two = luminance(b)
        return (maxOf(one, two) + 0.05) / (minOf(one, two) + 0.05)
    }

    private fun worstOf(appearance: AppearanceMode, isPlaying: Boolean): Double {
        compose.setContent {
            StoryArcTheme(appearance = appearance, useDynamicColor = false) {
                Box(Modifier.testTag("bar")) {
                    CompactPlayerBar(
                        title = "Sea Room",
                        chapter = "Three",
                        isPlaying = isPlaying,
                        progress = null,
                        labels = labels,
                        onToggle = {},
                        onOpen = {},
                    )
                }
            }
        }
        val map = compose.onNodeWithTag("bar").captureToImage().toPixelMap()
        val ground = map[1, 1]
        val strip = map.width - map.width / 8 until map.width
        var best = 1.0
        for (x in strip) for (y in 0 until map.height) {
            best = maxOf(best, contrast(map[x, y], ground))
        }
        return best
    }

    @Test
    fun `the play mark is readable on the dark bar`() {
        val ratio = worstOf(AppearanceMode.DARK, isPlaying = false)
        assertTrue("the play mark reaches only $ratio:1", ratio >= 3.0)
    }

    @Test
    fun `the pause mark is readable on the dark bar`() {
        val ratio = worstOf(AppearanceMode.DARK, isPlaying = true)
        assertTrue("the pause mark reaches only $ratio:1", ratio >= 3.0)
    }
}
