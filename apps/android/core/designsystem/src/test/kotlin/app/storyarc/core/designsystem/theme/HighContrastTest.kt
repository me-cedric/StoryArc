package app.storyarc.core.designsystem.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Increase Contrast, case for case with iOS's `PaletteTests`.
 *
 * The token *values* are gated by `pnpm tokens:check`. This guards the layer above:
 * that the setting reaches the palette, and that it strengthens the roles
 * `native-experience` names rather than whichever ones a view happened to think of.
 */
class HighContrastTest {
    @Test
    fun `the middle stop already counts as asking for more contrast`() {
        // Three stops in the system settings. A reader on medium has said the default
        // is not enough, which is the whole question this answers.
        assertFalse(isHighContrast(0f))
        assertTrue(isHighContrast(0.5f))
        assertTrue(isHighContrast(1f))
    }

    @Test
    fun `a device reporting less than standard is not asking for more`() {
        assertFalse(isHighContrast(-1f))
    }

    @Test
    fun `increase contrast strengthens the border and the weakest text tier`() {
        val standard = StoryArcPalette.Dark
        val increased = standard.strengthened()

        assertNotEquals(standard.borderSubtle, standard.borderStrong)
        assertEquals(standard.borderStrong, increased.borderSubtle)
        assertEquals(standard.textSecondary, increased.textTertiary)
    }

    @Test
    fun `increase contrast keeps a hierarchy to strengthen`() {
        // Promoting every tier would leave one tier. Primary still reads as primary.
        val increased = StoryArcPalette.Light.strengthened()

        assertNotEquals(increased.textPrimary, increased.textSecondary)
        assertEquals(StoryArcPalette.Light.accent, increased.accent)
    }

    @Test
    fun `increase contrast follows the appearance rather than replacing it`() {
        val increased = StoryArcPalette.OledDark.strengthened()

        assertEquals(StoryArcPalette.OledDark.surfaceCanvas, increased.surfaceCanvas)
    }
}
