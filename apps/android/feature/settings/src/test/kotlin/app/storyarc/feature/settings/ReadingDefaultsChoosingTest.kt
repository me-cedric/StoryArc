package app.storyarc.feature.settings

import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `reading-themes`, *Changing the global default*: a default change must not erase the
 * other fields of the stored default. Before this, the row's tap wrote a fresh
 * `ShelfSettings(theme, values)`, which put the transition, the spread offset, the
 * separator and the fit back to their built-in values on every preset tap.
 */
class ReadingDefaultsChoosingTest {

    @Test
    fun `the chosen preset and its typography land, and nothing else moves`() {
        val existing = ShelfSettings(
            theme = ReadingTheme(ThemePreset.PAPER),
            transition = PageTransition.PAGE_CURL,
            offsetsSpreads = true,
            showsPageSeparator = true,
            fit = PageFit.WIDTH,
        )

        val updated = choosingPreset(ThemePreset.CALM, existing)

        assertEquals("the chosen preset did not land", ThemePreset.CALM, updated.theme.preset)
        assertEquals(
            "the chosen preset's typography did not land",
            ThemePreset.CALM.values,
            updated.values,
        )
        assertTrue(
            "Choosing a preset moved a field it was never asked to touch. Before this, a" +
                " fresh ShelfSettings(theme, values) put the transition, the spread offset," +
                " the separator and the fit back to their built-in values on every tap.",
            updated.transition == PageTransition.PAGE_CURL &&
                updated.offsetsSpreads &&
                updated.showsPageSeparator &&
                updated.fit == PageFit.WIDTH,
        )
    }

    @Test
    fun `the new preset drops any deviation the old one carried`() {
        val existing = ShelfSettings(
            theme = ReadingTheme(ThemePreset.PAPER).deviating(on = ThemeAxis.LINE_SPACING),
        )

        val updated = choosingPreset(ThemePreset.CALM, existing)

        assertFalse(
            "The new preset must start clean: ReadingTheme(preset) is what adopting uses too.",
            updated.theme.isModified,
        )
    }

    @Test
    fun `a matte swatch works over a comic default stored as Original`() {
        val updated = matting("#E8EFE6", ReadingTheme(ThemePreset.ORIGINAL))

        assertEquals(
            "The matte did nothing over a comic default stored as Original. Original refuses" +
                " every palette, and the comic reader reads only the matte. `reading-themes`," +
                " *Separate defaults for reflowable and fixed-layout*.",
            "#E8EFE6",
            updated.custom?.background,
        )
    }

    @Test
    fun `no matte removes the colour and keeps the preset`() {
        val matted = matting("#E8EFE6", ReadingTheme(ThemePreset.CALM))

        val cleared = matting(null, matted)

        assertEquals(ThemePreset.CALM, cleared.preset)
        assertEquals("The no-matte swatch left a colour in force.", null, cleared.custom)
    }
}
