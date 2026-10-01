package app.storyarc.feature.reader

import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `ebook-reader`, *Fixed-layout EPUB*: "background colour ... remain[s] available, because
 * it applies to the container rather than the text" -- D34 builds that into the live comic
 * reader rather than leaving it reachable only from Settings' own per-series default.
 *
 * A mirror of `ReadingDefaultsChoosingTest`'s matte cases: the rule is the same four lines
 * either side applies, so the tests are the same shape.
 */
class ReaderMatteTest {

    @Test
    fun `a matte swatch works over a comic default stored as Original`() {
        val updated = matting("#E8EFE6", ReadingTheme(ThemePreset.ORIGINAL))

        assertEquals(
            "The matte did nothing over a theme stored as Original. Original refuses every" +
                " palette, and the comic reader reads only the matte.",
            "#E8EFE6",
            updated.custom?.background,
        )
    }

    @Test
    fun `no matte removes the colour and keeps the preset`() {
        val matted = matting("#E8EFE6", ReadingTheme(ThemePreset.CALM))

        val cleared = matting(null, matted)

        assertEquals(ThemePreset.CALM, cleared.preset)
        assertNull("The no-matte swatch left a colour in force.", cleared.custom)
    }

    @Test
    fun `a matte over a plain preset keeps that preset`() {
        val updated = matting("#1B2430", ReadingTheme(ThemePreset.QUIET))

        assertEquals(
            "choosing a matte changed the preset underneath it",
            ThemePreset.QUIET,
            updated.preset,
        )
        assertEquals("#1B2430", updated.custom?.background)
    }
}
