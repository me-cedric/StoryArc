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


    // Font size steps.

    @Test
    fun `the ladder spans at least seven steps and includes the publication's own size`() {
        // `reading-themes` asks for at least seven steps, which is the only
        // constraint on the count. What matters beyond that is that the
        // publication's own size is reachable — a ladder a reader cannot get back to
        // 100% on is a ladder they are stuck on.
        assertTrue(FontSizeStep.count >= 7)
        assertTrue(FontSizeStep.NORMAL in FontSizeStep.entries)
        assertEquals(1.0, FontSizeStep.NORMAL.fraction, 0.0001)
        assertTrue(FontSizeStep.NORMAL.position > 0)
        assertTrue(FontSizeStep.NORMAL.position < FontSizeStep.count - 1)
    }

    @Test
    fun `stepping stops at each end rather than wrapping`() {
        assertEquals(FontSizeStep.SMALLEST, FontSizeStep.SMALLEST.previous)
        assertEquals(FontSizeStep.HUGEST, FontSizeStep.HUGEST.next)
        assertEquals(FontSizeStep.NORMAL, FontSizeStep.NORMAL.next.previous)
    }

    @Test
    fun `the ladder rises monotonically, so a step is always a change`() {
        val sizes = FontSizeStep.entries.map { it.percent }
        assertEquals(sizes.sorted(), sizes)
        assertEquals(sizes.size, sizes.toSet().size)
    }

    // Preset values.

    @Test
    fun `Original overrides nothing but size`() {
        val values = ThemePreset.ORIGINAL.values
        assertEquals(ReaderTypeface.PUBLISHER, values.typeface)
        assertEquals(ReaderTextAlignment.PUBLISHER, values.textAlignment)
        assertEquals(ThemeValues(), values)
    }

    @Test
    fun `every other preset states a typeface`() {
        ThemePreset.entries.filter { it != ThemePreset.ORIGINAL }.forEach {
            assertTrue("$it should choose a face", it.values.typeface != ReaderTypeface.PUBLISHER)
        }
    }

    @Test
    fun `Bold opens larger and heavier, because that is what it is for`() {
        val bold = ThemePreset.BOLD.values
        assertTrue(bold.isBold)
        assertTrue(bold.fontSize.percent > FontSizeStep.NORMAL.percent)
        assertTrue(bold.lineHeight > ThemePreset.PAPER.values.lineHeight)
    }

    @Test
    fun `Focus has the widest margins, which is what a narrow measure means`() {
        val widest = ThemePreset.entries.maxOf { it.values.pageMargins }
        assertEquals(widest, ThemePreset.FOCUS.values.pageMargins, 0.0001)
    }

    @Test
    fun `Calm has the most generous line height`() {
        val tallest = ThemePreset.entries.maxOf { it.values.lineHeight }
        assertEquals(tallest, ThemePreset.CALM.values.lineHeight, 0.0001)
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
