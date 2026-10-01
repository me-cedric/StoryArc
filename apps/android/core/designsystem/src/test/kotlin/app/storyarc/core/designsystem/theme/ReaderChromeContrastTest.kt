package app.storyarc.core.designsystem.theme

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * `native-experience`: "translucent materials are replaced with the opaque fallback
 * declared in the design tokens" under Increase Contrast. The reader's capsule never
 * read the setting at all, so it stayed the scrim's 0.6 alpha regardless.
 *
 * A plain-value test of [readerChromeColourPair], the way `PaperGrainTest` asserts
 * [PaperGrain.isDrawn] with no composition -- the `rememberHighContrast()` wiring itself
 * has no test on either reader, the same gap `ReaderChromeColoursTest`'s own doc names
 * for the colours it already covers.
 */
class ReaderChromeContrastTest {
    @Test
    fun `the ordinary capsule is the translucent scrim`() {
        val (container, content) = readerChromeColourPair(isHighContrast = false, palette = StoryArcPalette.Light)

        assertEquals(StoryArcPalette.Light.scrim.copy(alpha = 0.6f), container)
        assertEquals(Color.White, content)
    }

    @Test
    fun `increase contrast replaces it with an opaque surface`() {
        val (container, content) = readerChromeColourPair(isHighContrast = true, palette = StoryArcPalette.Light)

        assertEquals("the container is fully opaque", 1f, container.alpha)
        assertEquals(StoryArcPalette.Light.surfaceOverlay, container)
        assertEquals(StoryArcPalette.Light.textPrimary, content)
    }

    @Test
    fun `the two containers are not the same colour`() {
        val ordinary = readerChromeColourPair(isHighContrast = false, palette = StoryArcPalette.Dark).first
        val contrasted = readerChromeColourPair(isHighContrast = true, palette = StoryArcPalette.Dark).first

        assertNotEquals(ordinary, contrasted)
    }
}
