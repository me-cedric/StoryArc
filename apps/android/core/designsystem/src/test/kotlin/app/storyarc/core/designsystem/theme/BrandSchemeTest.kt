package app.storyarc.core.designsystem.theme

import app.storyarc.core.designsystem.tokens.StoryArcColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * The brand palette dressed as a Material scheme — the path a reader takes when Material
 * You is off, and the only path the two appearances that decline it have.
 *
 * The token *values* are gated by `pnpm tokens:check`, which runs the WCAG maths on the
 * source of truth. This guards the layer above: that the Kotlin side wires the right
 * generated token into the right Material role. iOS's `PaletteTests` asserts the same
 * table for its own `Palette`, and nothing asserted this side of it until now.
 */
class BrandSchemeTest {

    @Test
    fun `One accent serves every appearance, which is why the violet was chosen`() {
        // The accent this replaced was a *pair*: a stronger light variant existed only
        // because the lighter one did not clear 3:1 on paper. The pink at the mark's first
        // arc stop is the same story — 7.24:1 on dark and 2.48:1 on light — and it is the
        // reason the accent is the violet from the middle of the arc instead.
        // `brand.accent` clears the floor on both canvases, 4.06 dark and 4.43 light, so
        // there is one token and deliberately no light-only twin.
        assertEquals(StoryArcColor.Brand.accent, StoryArcPalette.Dark.accent)
        assertEquals(StoryArcColor.Brand.accent, StoryArcPalette.Light.accent)
        assertEquals(StoryArcColor.Brand.accent, StoryArcPalette.OledDark.accent)

        assertEquals(StoryArcColor.Brand.accent, brandDarkScheme().primary)
        assertEquals(StoryArcColor.Brand.accent, brandLightScheme().primary)
        assertEquals(StoryArcColor.Brand.accent, brandOledDarkScheme().primary)
    }

    @Test
    fun `Secondary is the one role that still needs a light variant`() {
        // The two poles of the identity are the two ends of the mark's gradient, so the
        // pink is Material's `secondary` rather than a near-neighbour of the accent. It
        // is the role that keeps the pair the accent shed: at 72 % lightness the pink
        // reaches 2.48:1 on paper, so light takes `secondaryStrong` at 3.72:1.
        assertEquals(StoryArcColor.Brand.secondary, brandDarkScheme().secondary)
        assertEquals(StoryArcColor.Brand.secondary, brandOledDarkScheme().secondary)
        assertEquals(StoryArcColor.Brand.secondaryStrong, brandLightScheme().secondary)
    }

    @Test
    fun `The label on a filled button is light, because the accent is no longer light`() {
        // Not a preference. The accent this replaced sat at 70 % lightness, so a
        // near-black label on a filled button measured 6.91:1. `brand.accent` sits at
        // 58 %, and the same near-black label measures 4.06:1 — under WCAG's 4.5 floor
        // for normal-size text, which a button label is. Pure white is the only value in
        // the token set that clears 4.5 on this violet, at 4.77:1.
        //
        // `ACCENT_PAIRS` in the token build gates the pair. This asserts the wiring: that
        // `onPrimary` is that value on all three schemes and is not the canvas it used to
        // be on the two dark ones.
        val onPrimary = StoryArcColor.Light.surfaceRaised

        assertEquals(onPrimary, brandDarkScheme().onPrimary)
        assertEquals(onPrimary, brandOledDarkScheme().onPrimary)
        assertEquals(onPrimary, brandLightScheme().onPrimary)

        assertNotEquals(StoryArcColor.Dark.surfaceCanvas, brandDarkScheme().onPrimary)
        assertNotEquals(StoryArcColor.OledDark.surfaceCanvas, brandOledDarkScheme().onPrimary)
    }
}
