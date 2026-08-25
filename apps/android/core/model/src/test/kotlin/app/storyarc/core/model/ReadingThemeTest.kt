package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The theme model: which preset is on, which axes reach the page, and when a preset
 * counts as modified.
 *
 * `reading-themes` is specific about all three, and all three are the kind of rule
 * that is easy to get subtly wrong in a sheet full of sliders. iOS's
 * `ReadingThemeTests` asserts the same table.
 */
class ReadingThemeTest {

    // Presets.

    @Test
    fun `six presets, and only Original keeps the publisher's stylesheet`() {
        assertEquals(6, ThemePreset.entries.size)
        assertTrue(ThemePreset.ORIGINAL.keepsPublisherStyles)
        ThemePreset.entries.filter { it != ThemePreset.ORIGINAL }.forEach {
            assertFalse("$it should override the publisher", it.keepsPublisherStyles)
        }
    }

    @Test
    fun `nine axes, and the spacing ones need the publisher's styles off`() {
        assertEquals(9, ThemeAxis.entries.size)
        // From `design.md`'s mapping table — Readium's behaviour, not ours.
        listOf(ThemeAxis.FONT_SIZE, ThemeAxis.FONT_FAMILY, ThemeAxis.BOLD_TEXT, ThemeAxis.MARGINS)
            .forEach { assertFalse("$it reaches the page regardless", it.requiresPublisherStylesOff) }
        listOf(
            ThemeAxis.LINE_SPACING,
            ThemeAxis.CHARACTER_SPACING,
            ThemeAxis.WORD_SPACING,
            ThemeAxis.PARAGRAPH_SPACING,
            ThemeAxis.TEXT_ALIGNMENT,
        ).forEach { assertTrue("$it is overridden by publisher CSS", it.requiresPublisherStylesOff) }
    }

    // What reaches the page.

    @Test
    fun `under Original the spacing axes cannot reach the page`() {
        val theme = ReadingTheme(ThemePreset.ORIGINAL)

        assertTrue(theme.isEffective(ThemeAxis.FONT_SIZE))
        assertTrue(theme.isEffective(ThemeAxis.MARGINS))
        assertFalse(theme.isEffective(ThemeAxis.LINE_SPACING))
        assertFalse(theme.isEffective(ThemeAxis.TEXT_ALIGNMENT))
        // Four of nine, which is what the sheet has to show as unavailable.
        assertEquals(4, theme.effectiveAxes.size)
    }

    @Test
    fun `under every other preset all nine axes reach the page`() {
        ThemePreset.entries.filter { it != ThemePreset.ORIGINAL }.forEach {
            assertEquals(9, ReadingTheme(it).effectiveAxes.size)
        }
    }

    // Deviation.

    @Test
    fun `a fresh preset is active rather than modified`() {
        assertFalse(ReadingTheme(ThemePreset.PAPER).isModified)
    }

    @Test
    fun `moving an axis marks the preset modified and keeps it selected`() {
        val theme = ReadingTheme(ThemePreset.PAPER).deviating(ThemeAxis.LINE_SPACING)

        assertTrue(theme.isModified)
        // `reading-themes`: "the preset stays selected and is marked as modified".
        assertEquals(ThemePreset.PAPER, theme.preset)
        assertEquals(setOf(ThemeAxis.LINE_SPACING), theme.deviations)
    }

    @Test
    fun `an axis that cannot reach the page is not a deviation`() {
        // Nothing changed on the page, so calling Original modified would be a lie
        // the reader can see.
        val theme = ReadingTheme(ThemePreset.ORIGINAL).deviating(ThemeAxis.LINE_SPACING)

        assertFalse(theme.isModified)
        assertTrue(theme.deviations.isEmpty())
    }

    @Test
    fun `restoring puts the preset back without changing which one it is`() {
        val theme = ReadingTheme(ThemePreset.CALM)
            .deviating(ThemeAxis.FONT_SIZE)
            .deviating(ThemeAxis.MARGINS)
            .restored()

        assertEquals(ThemePreset.CALM, theme.preset)
        assertFalse(theme.isModified)
    }

    @Test
    fun `adopting a preset does not carry the last one's deviations across`() {
        // Otherwise the preset the reader just tapped is not the one they get.
        val theme = ReadingTheme(ThemePreset.PAPER)
            .deviating(ThemeAxis.FONT_SIZE)
            .adopting(ThemePreset.FOCUS)

        assertEquals(ThemePreset.FOCUS, theme.preset)
        assertFalse(theme.isModified)
    }

    // Transitions.

    @Test
    fun `Reduce Motion substitutes the fast fade, and leaves the scroll modes alone`() {
        assertEquals(PageTransition.FAST_FADE, PageTransition.PAGE_CURL.honoring(true))
        assertEquals(PageTransition.FAST_FADE, PageTransition.SLIDE.honoring(true))
        // Scrolling is not an animation the reader did not ask for.
        assertEquals(PageTransition.VERTICAL_SCROLL, PageTransition.VERTICAL_SCROLL.honoring(true))
        assertEquals(PageTransition.PAGE_CURL, PageTransition.PAGE_CURL.honoring(false))
    }
}
