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
 * **"The custom colour slot ... unchanged" is the reader's own named palette, kept in
 * `EpubReaderViewModel.customPalette` whether or not it is on the page — not `ReadingTheme.custom`,
 * which is only what is in force right now.** A reset drops `custom` the same as every other
 * axis, which is what puts the background back on the preset's own value; the slot elsewhere
 * is untouched, so the seventh card is still there afterwards.
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
    fun `the background returns to the preset's own value, the same as any other axis`() {
        val modified = ReadingTheme(
            preset = ThemePreset.CALM,
            deviations = setOf(ThemeAxis.LINE_SPACING),
            custom = mine,
        )

        assertNull(
            "The reset kept the reader's own colour in force, so the background did not" +
                " return to Calm's own value — the one axis \"every axis returns to that" +
                " preset's published value\" did not reach. The custom colour *slot*" +
                " `reading-themes` lists among the things a reset leaves alone is" +
                " `EpubReaderViewModel.customPalette`, kept whether or not it is in force;" +
                " `custom` here is only what is on the page now.",
            modified.restored().custom,
        )
    }

    @Test
    fun `a preset with nothing deviating is already restored, and says so`() {
        for (preset in ThemePreset.entries) {
            val clean = ReadingTheme(preset = preset)

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
