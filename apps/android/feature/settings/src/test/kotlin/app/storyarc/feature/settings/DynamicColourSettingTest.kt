package app.storyarc.feature.settings

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Material You opt-out.
 *
 * `native-experience`: the scheme "is the StoryArc palette by default, with a setting to
 * take the device's wallpaper colours instead". The default moved on 2026-10-06: one brand
 * accent reached iOS and not Android, and which colour an Android reader met was decided by
 * their wallpaper. The switch did not move, and neither did an install that already held an
 * answer.
 *
 * Android-only. iOS has no dynamic colour to opt out of, so there is deliberately no
 * mirrored test there.
 */
class DynamicColourSettingTest {

    @Test
    fun `a fresh install wears the brand palette, not the wallpaper`() {
        assertFalse(AppSettings.Defaults.useDynamicColor)
    }

    @Test
    fun `turning it on changes nothing else, and a reset undoes only it`() {
        // `SettingsStore.reset()` writes `Defaults`, so what a reset restores is decided
        // here rather than there. The two assertions are the two halves that matter: the
        // switch is the only field it moves, and `Defaults` is the state it returns to.
        val opted = AppSettings.Defaults.copy(useDynamicColor = true)

        assertNotEquals(AppSettings.Defaults, opted)
        assertEquals(AppSettings.Defaults, opted.copy(useDynamicColor = false))
    }

    @Test
    fun `an install that already answered keeps its answer when the default moves`() {
        // The clause a reader would actually feel, and the one nothing asserted before the
        // default moved: a stored record is read, not re-derived, so a reader who chose the
        // wallpaper -- or merely lived with it -- does not have their app change colour on an
        // update. Only a fresh install and a reset read `Defaults`.
        val stored = AppSettings.Defaults.copy(useDynamicColor = true)

        assertTrue(stored.useDynamicColor)
        assertNotEquals(AppSettings.Defaults.useDynamicColor, stored.useDynamicColor)
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
