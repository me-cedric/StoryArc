package app.storyarc.core.designsystem.theme

import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What an appearance resolves to.
 *
 * `settings-and-about` names four and is specific about the one that is not what its
 * name implies: OLED Dark makes chrome true black and deliberately does *not* make the
 * reader surface true black. iOS's `AppearanceTests` asserts the same table.
 */
class AppearanceTest {

    @Test
    fun `Four appearances, with System first and Natural deliberately absent`() {
        assertEquals(4, AppearanceMode.entries.size)
        assertEquals(AppearanceMode.SYSTEM, AppearanceMode.entries.first())
        // Natural is "a theme rather than an appearance" and carries its own light and
        // dark variants, so putting it here would force a choice the spec avoids.
        assertFalse(AppearanceMode.entries.any { it.name.contains("NATURAL") })
    }

    @Test
    fun `Only OLED Dark asks for the true-black palette`() {
        assertTrue(AppearanceMode.OLED_DARK.isTrueBlack)
        AppearanceMode.entries.filter { it != AppearanceMode.OLED_DARK }
            .forEach { assertFalse(it.name, it.isTrueBlack) }
    }

    @Test
    fun `OLED Dark makes chrome true black and the reader surface deliberately not`() {
        // The whole point of the scenario: pure black smears on OLED during a page turn,
        // which is the exact motion this app is built around.
        val palette = StoryArcPalette.OledDark
        assertNotEquals(palette.surfaceCanvas, palette.surfaceReader)
        assertEquals(StoryArcColor.OledDark.surfaceCanvas, palette.surfaceCanvas)
        assertEquals(StoryArcColor.OledDark.surfaceReader, palette.surfaceReader)
    }
}
