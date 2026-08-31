package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That resetting a modified preset restores that preset, and nothing else.
 *
 * `reading-themes`, *The reset names what it restores*:
 *
 * > **THEN** the action names that preset — the reader who modified Calm is offered Calm
 * > back, not an unnamed default
 * > **AND** every axis returns to that preset's published value, including any the reader
 * > never touched
 * > **AND** the other five presets, the custom colour slot, the per-series memory and the
 * > global default are unchanged, because a reset is not a factory reset
 *
 * **The custom-slot clause is the one that failed, on both platforms.** `restored()` was
 * written as `ReadingTheme(preset)`, which is `adopting`'s body — and adopting a preset drops
 * the custom palette *on purpose*, because tapping one of the six is how a reader leaves their
 * own colours. A reset is not that act. A reader who had made a palette, chosen Calm, and
 * nudged the line spacing lost the palette by putting the line spacing back.
 *
 * iOS mirrors this suite as `ThemeResetTests`, case for case.
 */
class ThemeResetTest {

    /** A palette the reader made, distinguishable from anything a preset would produce. */
    private val mine = ReaderPalette(name = "Mine", background = "#123456", foreground = "#FEDCBA")

    @Test
    fun `every axis returns to the preset's own values, including untouched ones`() {
        val modified = ReadingTheme(
            preset = ThemePreset.CALM,
            deviations = setOf(ThemeAxis.LINE_SPACING, ThemeAxis.MARGINS),
        )

        val reset = modified.restored()

        assertEquals(ThemePreset.CALM, reset.preset)
        assertTrue("no axis is left deviating, touched or not", reset.deviations.isEmpty())
        assertTrue(!reset.isModified)
    }

    @Test
    fun `the custom colour slot survives, because a reset is not a factory reset`() {
        val modified = ReadingTheme(
            preset = ThemePreset.CALM,
            deviations = setOf(ThemeAxis.LINE_SPACING),
            custom = mine,
        )

        assertEquals(
            "The reset discarded the reader's own palette. `reading-themes` lists the custom" +
                " colour slot among the things a reset leaves alone: \"a reset is not a" +
                " factory reset\". Dropping it is what adopting a preset does, and that is a" +
                " different act.",
            mine,
            modified.restored().custom,
        )
    }

    @Test
    fun `a preset with nothing deviating is already restored, and says so`() {
        for (preset in ThemePreset.entries) {
            val clean = ReadingTheme(preset = preset, custom = mine)

            assertTrue(
                "$preset with no deviations reports itself modified, so the reset action" +
                    " would be offered for it. `reading-themes`: the action is \"absent" +
                    " rather than present and doing nothing, because a control that never" +
                    " changes anything teaches a reader to distrust the ones that do\".",
                !clean.isModified,
            )
            assertEquals("restoring it changes nothing", clean, clean.restored())
        }
    }

    @Test
    fun `adopting a preset still drops the custom palette, which is a different act`() {
        val mineInForce = ReadingTheme(
            preset = ThemePreset.CALM,
            deviations = setOf(ThemeAxis.MARGINS),
            custom = mine,
        )

        assertNull(
            "Tapping one of the six presets must still leave the reader's own colours" +
                " behind — `reading-themes` says a preset applies \"every axis the preset" +
                " defines ... at once\", and a preset that kept a custom background would" +
                " not be the preset that was tapped. This is the distinction the reset fix" +
                " must not blur.",
            mineInForce.adopting(ThemePreset.PAPER).custom,
        )
    }
}
