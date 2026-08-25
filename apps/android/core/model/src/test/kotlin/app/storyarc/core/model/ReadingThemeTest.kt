package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    // Contrast.

    @Test
    fun `Black on white is the extreme WCAG defines, and a colour on itself is the floor`() {
        assertEquals(21.0, ReadingContrast.ratio("#000000", "#FFFFFF"), 0.01)
        assertEquals(21.0, ReadingContrast.ratio("#FFFFFF", "#000000"), 0.01)
        assertEquals(1.0, ReadingContrast.ratio("#3A5F8A", "#3A5F8A"), 0.0001)
    }

    @Test
    fun `A colour it cannot read is the worst ratio, never the best`() {
        // The failure mode that matters: a typo must not be the reason a pairing is
        // accepted, so an unreadable colour reports 1 rather than null or 21.
        assertEquals(1.0, ReadingContrast.ratio("not a colour", "#FFFFFF"), 0.0001)
        assertNull(ReadingContrast.luminance("#12345"))
        // Three-digit hex is legal CSS and a picker may hand one over.
        assertEquals(21.0, ReadingContrast.ratio("#fff", "#000000"), 0.01)
    }

    @Test
    fun `The runtime maths agrees with the token pipeline's, to four places`() {
        // Golden values from `packages/design-tokens/scripts/oklch.mjs`, which is what
        // fails the build when a reading theme drops below 7 to 1. If the two drifted,
        // a pairing could pass the gate and be refused in the sheet, or worse the
        // other way round. Paper's own pair, and the mid-grey ceiling.
        assertEquals(15.4044, ReadingContrast.ratio("#F5F1EC", "#1D1A17"), 0.0001)
        assertEquals(5.3172, ReadingContrast.ratio("#808080", "#000000"), 0.0001)
    }

    @Test
    fun `A derived text colour is the better of black and white`() {
        assertEquals("#000000", ReaderPalette.derived("n", "#FFFFFF").foreground)
        assertEquals("#FFFFFF", ReaderPalette.derived("n", "#101010").foreground)
    }

    @Test
    fun `A mid-tone background is reported as unable to reach AAA rather than dressed up`() {
        // Grey tops out near 5.3 against black. The honest answer is that no text
        // colour reaches 7 to 1 on it — silently returning black would look like a pass.
        val grey = ReaderPalette.derived("grey", "#808080")
        assertTrue(grey.isReadable)
        assertFalse(grey.meetsAAA)
    }

    @Test
    fun `A pairing below AA is refused, and the ratio survives to be shown`() {
        // `reading-themes` refuses below 4.5 to 1 "with the measured ratio stated", so
        // the attempt has to exist as a value long enough to be measured.
        val tried = ReaderPalette.derived("n", "#FFFFFF").copy(foreground = "#DDDDDD")
        assertFalse(tried.isReadable)
        assertTrue(tried.contrast > 1)
    }

    // The seventh slot.

    @Test
    fun `Custom colours sit alongside the presets and keep the typography`() {
        val palette = ReaderPalette.derived("Sea", "#0B2027")
        val theme = ReadingTheme(ThemePreset.CALM, setOf(ThemeAxis.LINE_SPACING)).adopting(palette)
        assertTrue(theme.isCustom)
        // The preset is not overwritten, and the reader's line height survives.
        assertEquals(ThemePreset.CALM, theme.preset)
        assertEquals(setOf(ThemeAxis.LINE_SPACING), theme.deviations)
        assertNull(theme.discardingCustomColours().custom)
    }

    @Test
    fun `Tapping one of the six leaves the reader's own palette behind`() {
        val theme = ReadingTheme().adopting(ReaderPalette.derived("Sea", "#0B2027"))
        assertNull(theme.adopting(ThemePreset.FOCUS).custom)
        assertNull(theme.restored().custom)
    }

    @Test
    fun `Original refuses custom colours, because the publisher's are the point`() {
        val theme = ReadingTheme(ThemePreset.ORIGINAL)
            .adopting(ReaderPalette.derived("Sea", "#0B2027"))
        assertFalse(theme.isCustom)
    }

    // Axis units.

    @Test
    fun `An axis with a slider can say what its number means, and one without says nothing`() {
        // The invariant that matters: a tenth axis added to `sliderRange` and
        // forgotten here would ship a slider a screen reader reads as a bare float.
        ThemeAxis.entries.forEach { axis ->
            assertEquals(axis.toString(), axis.sliderRange != null, axis.unit != null)
            assertEquals(axis.toString(), axis.sliderRange != null, axis.step != null)
        }
    }

    @Test
    fun `A whole ladder of adjustments crosses an axis from end to end`() {
        ThemeAxis.entries.forEach { axis ->
            val range = axis.sliderRange ?: return@forEach
            val step = axis.step ?: return@forEach
            assertEquals(
                axis.toString(),
                range.endInclusive,
                range.start + step * STEPS_PER_AXIS,
                0.0001,
            )
        }
    }
}
