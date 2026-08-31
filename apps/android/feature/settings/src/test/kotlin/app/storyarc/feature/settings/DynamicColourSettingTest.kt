package app.storyarc.feature.settings

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Material You opt-out.
 *
 * `native-experience`: the scheme "derives from the user's wallpaper by default, with a
 * setting to use the StoryArc palette instead". Until this existed there was no setting and
 * no field, and the only way back to the brand palette was to choose OLED Dark -- a
 * different setting meaning a different thing.
 *
 * Android-only. iOS has no dynamic colour to opt out of, so there is deliberately no
 * mirrored test there.
 */
class DynamicColourSettingTest {

    @Test
    fun `the wallpaper dresses the chrome until a reader says otherwise`() {
        assertTrue(AppSettings.Defaults.useDynamicColor)
    }

    @Test
    fun `a reset puts the wallpaper back`() {
        val chosen = AppSettings.Defaults.copy(useDynamicColor = false)

        assertNotEquals(chosen, AppSettings.Defaults)
        assertTrue(AppSettings.Defaults.useDynamicColor)
    }

    @Test
    fun `the row explains itself under OLED Dark and only there`() {
        // The agreement the setting has to keep: true black and a wallpaper-derived wash
        // are incompatible asks, `StoryArcTheme` already resolves it in true black's favour,
        // and the row says so rather than claiming a control it does not have.
        assertEquals(
            R.string.appearance_dynamic_colour_oled_note,
            dynamicColourNoteRes(AppearanceMode.OLED_DARK),
        )
        AppearanceMode.entries.filter { !it.isTrueBlack }.forEach { appearance ->
            assertEquals(
                appearance.name,
                R.string.appearance_dynamic_colour_note,
                dynamicColourNoteRes(appearance),
            )
        }
    }

    @Test
    fun `the setting lives on the appearance screen and search can reach it`() {
        assertEquals(SettingsGroup.APPEARANCE, SettingsAnchor.DYNAMIC_COLOUR.group)
        assertEquals(
            SettingsAnchor.DYNAMIC_COLOUR,
            SettingsGroup.search("wallpaper").firstOrNull()?.anchor,
        )
    }

    @Test
    fun `the reader who wants the brand palette back can search for what they want it for`() {
        // Not for what the screen calls it: nobody searches settings for "dynamic colour"
        // when what they mean is "stop taking my wallpaper".
        listOf("material", "brand", "palette", "dynamic").forEach { term ->
            assertEquals(
                term,
                SettingsAnchor.DYNAMIC_COLOUR,
                SettingsGroup.search(term).firstOrNull()?.anchor,
            )
        }
    }
}
