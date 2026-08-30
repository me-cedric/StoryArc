package app.storyarc.core.designsystem.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * The three theme-wide rules that had no enforcement before: the shape scale is wired,
 * the type scale is Material's, and dynamic colour stops at the chrome.
 *
 * Each of these is a single line in `Theme.kt` with an app-wide blast radius, which is
 * exactly the kind of line that gets deleted during an unrelated refactor and noticed
 * three screens later.
 */
class ThemeScalesTest {

    @Test
    fun `every Material shape slot is a StoryArc radius`() {
        assertEquals(RoundedCornerShape(StoryArcRadius.sm), StoryArcShapes.extraSmall)
        assertEquals(RoundedCornerShape(StoryArcRadius.md), StoryArcShapes.small)
        assertEquals(RoundedCornerShape(StoryArcRadius.lg), StoryArcShapes.medium)
        assertEquals(RoundedCornerShape(StoryArcRadius.xl), StoryArcShapes.large)
        assertEquals(RoundedCornerShape(StoryArcRadius.sheet), StoryArcShapes.extraLarge)
    }

    /**
     * The regression that mattered: for as long as `MaterialTheme.shapes` went unset, every
     * assertion above would still have passed against a constant nobody handed to Material.
     * Being *different* from the default is what proves the tokens are the ones in force.
     */
    @Test
    fun `the shape scale is not Material's default`() {
        assertNotEquals(Shapes().extraSmall, StoryArcShapes.extraSmall)
        assertNotEquals(Shapes().small, StoryArcShapes.small)
        assertNotEquals(Shapes().medium, StoryArcShapes.medium)
        assertNotEquals(Shapes().large, StoryArcShapes.large)
    }

    /**
     * `ui-revamp-2026-08` §4.6: Material slots carry Material sizes. This used to pour
     * iOS's numbers in — 34 sp display, 17 sp body — and leave three slots unset.
     */
    @Test
    fun `the type scale is Material's own, and no slot is left to fall through`() {
        assertEquals(57.sp, StoryArcTypography.displayLarge.fontSize)
        assertEquals(45.sp, StoryArcTypography.displayMedium.fontSize)
        assertEquals(36.sp, StoryArcTypography.displaySmall.fontSize)
        assertEquals(22.sp, StoryArcTypography.titleLarge.fontSize)
        assertEquals(16.sp, StoryArcTypography.bodyLarge.fontSize)
        assertEquals(24.sp, StoryArcTypography.bodyLarge.lineHeight)
    }

    /**
     * The colour rule: a wallpaper dresses the chrome and never reaches the ground the
     * artwork sits on. Stated with a scheme whose every role is the same implausible
     * colour, so what survives and what does not is unambiguous.
     */
    @Test
    fun `grounding a scheme replaces the content ground and nothing else`() {
        val wallpaper = lightColorScheme(
            primary = Color.Magenta,
            surface = Color.Magenta,
            surfaceContainer = Color.Magenta,
            background = Color.Magenta,
            onBackground = Color.Magenta,
            scrim = Color.Magenta,
        )
        val palette = StoryArcPalette.Dark

        val grounded = wallpaper.groundedInContent(palette)

        assertEquals(palette.surfaceCanvas, grounded.background)
        assertEquals(palette.textPrimary, grounded.onBackground)
        assertEquals(palette.scrim, grounded.scrim)
        // The chrome keeps every bit of the wallpaper it arrived with.
        assertEquals(Color.Magenta, grounded.primary)
        assertEquals(Color.Magenta, grounded.surface)
        assertEquals(Color.Magenta, grounded.surfaceContainer)
    }

    /**
     * Grounding a StoryArc scheme is a no-op, which is what lets it run unconditionally
     * rather than behind a branch somebody has to keep true.
     *
     * Role by role rather than scheme against scheme: `ColorScheme` compares by identity,
     * so `assertEquals` on two of them asks a question about allocation.
     */
    @Test
    fun `grounding a brand scheme changes nothing`() {
        val palette = StoryArcPalette.Light
        val brand = lightColorScheme(
            background = palette.surfaceCanvas,
            onBackground = palette.textPrimary,
            scrim = palette.scrim,
        )

        val grounded = brand.groundedInContent(palette)

        assertEquals(brand.background, grounded.background)
        assertEquals(brand.onBackground, grounded.onBackground)
        assertEquals(brand.scrim, grounded.scrim)
    }
}
