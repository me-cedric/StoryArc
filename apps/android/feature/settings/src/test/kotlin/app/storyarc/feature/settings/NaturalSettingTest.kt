package app.storyarc.feature.settings

import app.storyarc.core.model.AppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The Natural row on the Appearance screen.
 *
 * `settings-and-about` lists Natural in the same table as the four appearances and then
 * says it "sits alongside them rather than inside the light/dark polarity" — so it is a
 * switch under the four rather than a fifth radio row, and one appearance declines it.
 *
 * iOS has the same row and the same rule; what it does not have is the dynamic-colour
 * consequence below, because Material You is Android's.
 */
class NaturalSettingTest {

    @Test
    fun `the row explains itself under OLED Dark and only there`() {
        assertEquals(
            R.string.appearance_natural_unavailable,
            naturalUnavailableRes(AppearanceMode.OLED_DARK),
        )
        AppearanceMode.entries.filter { !it.isTrueBlack }.forEach { appearance ->
            assertNull(appearance.name, naturalUnavailableRes(appearance))
        }
    }

    @Test
    fun `Natural takes the wallpaper's place, and the colour row says so`() {
        // Natural's accents reach the whole app by design, so a wallpaper-derived wash
        // beside them would be two themes at once. The row explains the absence rather
        // than leaving a switch that silently does nothing — the same treatment OLED Dark
        // already gets, for the same shape of reason.
        assertEquals(
            R.string.appearance_dynamic_colour_natural_note,
            dynamicColourNoteRes(AppearanceMode.DARK, isNatural = true),
        )
        // True black still wins the explanation where both apply: it is the one that
        // cannot be combined with Natural at all.
        assertEquals(
            R.string.appearance_dynamic_colour_oled_note,
            dynamicColourNoteRes(AppearanceMode.OLED_DARK, isNatural = true),
        )
        assertEquals(
            R.string.appearance_dynamic_colour_note,
            dynamicColourNoteRes(AppearanceMode.DARK, isNatural = false),
        )
    }

    @Test
    fun `the setting lives on the appearance screen and search can reach it`() {
        assertEquals(SettingsGroup.APPEARANCE, SettingsAnchor.NATURAL_THEME.group)
        // Not for what the screen calls it: a reader who wants paper searches for paper.
        listOf("natural", "paper", "grain", "texture", "warm").forEach { term ->
            assertEquals(
                term,
                SettingsAnchor.NATURAL_THEME,
                SettingsGroup.search(term).firstOrNull()?.anchor,
            )
        }
    }
}
