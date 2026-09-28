package app.storyarc.feature.epubreader

import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What reaches Readium.
 *
 * The domain decides what a theme *is*; this is the only place that knows what Readium
 * calls each part, so it is the only place a rename or an inert preference can hide. Runs
 * on Robolectric because `preferences(values:)` reaches `android.graphics.Color.parseColor`.
 * iOS mirrors this suite in `ReadiumMappingTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReadiumMappingTest {

    @Test
    fun `original overrides size, family, weight and margins, and leaves the rest to the publisher`() {
        val theme = ReadingTheme(preset = ThemePreset.ORIGINAL)
        var values = theme.preset.values.copy(fontSize = FontSizeStep.LARGE, pageMargins = 2.1)
        // Original's own default is PUBLISHER, whose `readium` mapping is nil by design —
        // "leaves the publication's own family in place". A reader who has moved the axis
        // holds a real face, which is the case this asserts.
        values = values.copy(typeface = ReaderTypeface.SERIF)

        val preferences = theme.preferences(values = values)

        assertEquals(true, preferences.publisherStyles)
        assertEquals(FontSizeStep.LARGE.fraction, preferences.fontSize!!, 0.0)
        // `ThemeAxis.requiresPublisherStylesOff` says these three reach the page
        // regardless of `publisherStyles`.
        assertNotNull(
            "Original overrode no typeface. `ThemeAxis.requiresPublisherStylesOff` puts" +
                " fontFamily with size, weight and margins, on the side Readium honours" +
                " whatever `publisherStyles` is set to.",
            preferences.fontFamily,
        )
        assertEquals(2.1, preferences.pageMargins!!, 0.0)
        // Everything the publisher styles: untouched, not set to a default.
        assertNull(preferences.backgroundColor)
        assertNull(preferences.textColor)
        assertNull(preferences.hyphens)
        assertNull(preferences.lineHeight)
        assertNull(preferences.textAlign)
    }

    @Test
    fun `bold raises the weight under Original too`() {
        val theme = ReadingTheme(preset = ThemePreset.ORIGINAL)
        val values = theme.preset.values.copy(isBold = true)

        val preferences = theme.preferences(values = values)

        assertNotNull(
            "Bold did nothing under Original. `boldText` is in the `false` half of" +
                " `ThemeAxis.requiresPublisherStylesOff`, so the control was live while" +
                " it changed nothing on the page — the defect `reading-themes`'s" +
                " publisher-styles scenario forbids for a control shown as usable.",
            preferences.fontWeight,
        )
    }

    @Test
    fun `every other preset takes over, with colours from the tokens`() {
        ThemePreset.entries.filter { it != ThemePreset.ORIGINAL }.forEach { preset ->
            val theme = ReadingTheme(preset = preset)
            val preferences = theme.preferences(values = preset.values)

            assertEquals("$preset should override", false, preferences.publisherStyles)
            assertNotNull("$preset needs a background", preferences.backgroundColor)
            assertNotNull("$preset needs a text colour", preferences.textColor)
            assertEquals(preset.values.pageMargins, preferences.pageMargins!!, 0.0)
        }
    }
}
