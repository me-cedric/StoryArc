package app.storyarc.core.designsystem.theme

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.control.OutlinedButton
import app.storyarc.core.designsystem.control.TextButton
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `close-the-audited-gaps` 27.4, owner answer O30: accent and danger text reach 4.5:1.
 *
 * `pnpm tokens:check` gates the token values. This gates the wiring: a text button and an
 * outlined button draw their label in the palette's `accentText`, the schemes' `error` role is
 * `dangerText`, and under dynamic colour both follow the wallpaper scheme.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AccentTextTest {

    @get:Rule
    val compose = createComposeRule()

    private val looks = listOf(
        Look("light", AppearanceMode.LIGHT, StoryArcPalette.Light),
        Look("dark", AppearanceMode.DARK, StoryArcPalette.Dark),
        Look("true black", AppearanceMode.OLED_DARK, StoryArcPalette.OledDark),
    )

    @Test
    fun `a text button label is the accent text, not the accent fill`() {
        val drawn = drawIn { record -> TextButton(onClick = {}) { record(LocalContentColor.current) } }
        for (look in looks) {
            assertEquals(look.name, look.palette.accentText, drawn.getValue(look.name))
            assertNotEquals("${look.name} is the accent fill", StoryArcColor.Brand.accent, drawn.getValue(look.name))
        }
    }

    @Test
    fun `an outlined button label is the accent text, not the accent fill`() {
        val drawn = drawIn { record -> OutlinedButton(onClick = {}) { record(LocalContentColor.current) } }
        for (look in looks) {
            assertEquals(look.name, look.palette.accentText, drawn.getValue(look.name))
        }
    }

    @Test
    fun `the error role of a brand scheme is the danger text of its ramp`() {
        assertEquals(StoryArcColor.Light.dangerText, brandLightScheme().error)
        assertEquals(StoryArcColor.Dark.dangerText, brandDarkScheme().error)
        assertEquals(StoryArcColor.OledDark.dangerText, brandOledDarkScheme().error)
        assertEquals(StoryArcColor.NaturalLight.dangerText, naturalLightScheme().error)
        assertEquals(StoryArcColor.NaturalDark.dangerText, naturalDarkScheme().error)
        assertNotEquals(StoryArcColor.Status.danger, brandLightScheme().error)
    }

    @Test
    fun `under dynamic colour the text colours follow the wallpaper scheme`() {
        var accentText = Color.Unspecified
        var primary = Color.Unspecified
        var dangerText = Color.Unspecified
        var error = Color.Unspecified
        compose.setContent {
            StoryArcTheme(appearance = AppearanceMode.LIGHT, useDynamicColor = true, natural = false) {
                accentText = LocalStoryArcPalette.current.accentText
                dangerText = LocalStoryArcPalette.current.dangerText
                primary = MaterialTheme.colorScheme.primary
                error = MaterialTheme.colorScheme.error
                Text("")
            }
        }
        compose.waitForIdle()
        assertEquals(primary, accentText)
        assertEquals(error, dangerText)
        assertNotEquals(StoryArcPalette.Light.accentText, accentText)
    }

    @Test
    fun `Natural keeps its own accent text`() {
        var accentText = Color.Unspecified
        compose.setContent {
            StoryArcTheme(appearance = AppearanceMode.LIGHT, useDynamicColor = true, natural = true) {
                accentText = LocalStoryArcPalette.current.accentText
                Text("")
            }
        }
        compose.waitForIdle()
        assertEquals(StoryArcColor.NaturalLight.accentText, accentText)
    }

    private class Look(val name: String, val appearance: AppearanceMode, val palette: StoryArcPalette)

    /** Draws [button] once in each look, side by side, and returns the label colour each one drew. */
    private fun drawIn(button: @Composable (record: (Color) -> Unit) -> Unit): Map<String, Color> {
        val drawn = mutableMapOf<String, Color>()
        compose.setContent {
            for (look in looks) {
                StoryArcTheme(appearance = look.appearance, useDynamicColor = false, natural = false) {
                    button { drawn[look.name] = it }
                }
            }
            Text("")
        }
        compose.waitForIdle()
        return drawn
    }
}
