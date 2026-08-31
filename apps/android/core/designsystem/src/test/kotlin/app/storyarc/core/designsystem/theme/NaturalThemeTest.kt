package app.storyarc.core.designsystem.theme

import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Natural, which is a second axis rather than a fifth appearance.
 *
 * `AppearanceTest` already asserts what Natural is *not* — an entry in [AppearanceMode].
 * This asserts what it is: an independent switch that crosses the polarity it sits beside,
 * with one appearance that declines it. iOS's `NaturalThemeTests` asserts the same table.
 */
class NaturalThemeTest {

    @Test
    fun `Natural crosses light and dark rather than replacing either`() {
        // The whole reason it is not an AppearanceMode entry: choosing it does not cost
        // the reader their choice of polarity.
        assertNotEquals(StoryArcPalette.NaturalLight, StoryArcPalette.NaturalDark)
        assertNotEquals(StoryArcPalette.NaturalLight, StoryArcPalette.Light)
        assertNotEquals(StoryArcPalette.NaturalDark, StoryArcPalette.Dark)
    }

    @Test
    fun `Natural follows System, Light and Dark alike`() {
        listOf(AppearanceMode.SYSTEM, AppearanceMode.LIGHT, AppearanceMode.DARK)
            .forEach { appearance ->
                assertTrue(appearance.name, NaturalTheme.isAvailable(appearance))
                assertTrue(appearance.name, NaturalTheme.applies(true, appearance))
            }
    }

    @Test
    fun `OLED Dark declines Natural, because true black is why it exists`() {
        // Warm cream stock and true black are opposite asks. The appearance that made a
        // promise about the black point keeps it, and the switch says why rather than
        // sitting there doing nothing.
        assertFalse(NaturalTheme.isAvailable(AppearanceMode.OLED_DARK))
        assertFalse(NaturalTheme.applies(true, AppearanceMode.OLED_DARK))
    }

    @Test
    fun `Off, Natural applies nowhere`() {
        AppearanceMode.entries.forEach { appearance ->
            assertFalse(appearance.name, NaturalTheme.applies(false, appearance))
        }
    }

    @Test
    fun `Natural's accents are clay, and they follow the same rule ember does`() {
        // `design.md`: Natural's accents reach the whole app, "so the theme is coherent
        // rather than bolted onto the reader". Earthier than ember, and the light variant
        // takes the stronger one for the reason light takes emberStrong — clay at 66 %
        // lightness does not clear 3:1 on warm paper. `pnpm tokens:check` gates both pairs.
        assertEquals(StoryArcColor.Brand.clayStrong, StoryArcPalette.NaturalLight.accent)
        assertEquals(StoryArcColor.Brand.clay, StoryArcPalette.NaturalDark.accent)
        assertEquals(StoryArcColor.Brand.clayStrong, naturalLightScheme().primary)
        assertEquals(StoryArcColor.Brand.clay, naturalDarkScheme().primary)
    }

    @Test
    fun `Natural's reader surface is its own, and is not the canvas`() {
        // The surface the grain is drawn over. It is a colour in the tokens, so the
        // palette holds wherever the texture is absent — which below API 33 is everywhere.
        val light = StoryArcPalette.NaturalLight
        val dark = StoryArcPalette.NaturalDark

        assertEquals(StoryArcColor.NaturalLight.surfaceReader, light.surfaceReader)
        assertEquals(StoryArcColor.NaturalDark.surfaceReader, dark.surfaceReader)
        assertNotEquals(light.surfaceCanvas, light.surfaceReader)
        assertNotEquals(dark.surfaceCanvas, dark.surfaceReader)
    }

    @Test
    fun `Increase Contrast reaches Natural the way it reaches every other palette`() {
        val strengthened = StoryArcPalette.NaturalLight.strengthened()

        assertEquals(StoryArcPalette.NaturalLight.borderStrong, strengthened.borderSubtle)
        assertEquals(StoryArcPalette.NaturalLight.textSecondary, strengthened.textTertiary)
    }

    @Test
    fun `The stored key is one constant, and iOS stores the same one`() {
        assertEquals("storyarc.appearance.natural", NaturalTheme.STORAGE_KEY)
    }
}
