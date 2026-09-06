package app.storyarc.feature.epubreader

import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingContrast
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * What a colour pairing will be like to read, said in words before the number that measures it.
 *
 * `reading-themes` / *Custom colour* requires a refused pairing to be stated "with the measured
 * ratio stated". It does not require the ratio to be the *only* thing stated, and a reader
 * choosing a background colour cannot act on "4.7 to 1" — a number nobody can interpret is
 * decoration that looks like information. So a band leads, in plain words, and the measured ratio
 * follows it as supporting detail. Nothing is removed: the refusal keeps its measurement, because
 * a reader who is refused deserves to know by how much and a developer reading a bug report needs
 * the number.
 *
 * **The two boundaries are the domain's own.** [ReadingContrast.AAA] at 7, which a derived text
 * colour aims for and every built-in preset clears, and [ReadingContrast.AA] at 4.5, below which
 * the sheet refuses the pairing outright. A band drawn at any other number would let the words and
 * the refusal disagree about the same pairing.
 *
 * The four languages are resolved through Robolectric's own qualifiers, so what is asserted is the
 * value `values-fr/strings.xml` really holds rather than a copy of it written here.
 *
 * iOS mirrors this suite in `PageColourBandTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PageColourBandTest {

    // region The boundaries

    @Test
    fun `seven to one reads comfortably, and just below it does not`() {
        assertEquals("above 7 to 1 is the comfortable band", ReadingComfort.EASY, band(7.01))
        assertEquals("7 to 1 itself is the comfortable band", ReadingComfort.EASY, band(ReadingContrast.AAA))
        assertEquals("just below 7 to 1 leaves the comfortable band", ReadingComfort.TIRING, band(6.99))
    }

    @Test
    fun `four point five to one is still readable, and just below it is refused`() {
        assertEquals("above 4.5 to 1 is the readable band", ReadingComfort.TIRING, band(4.51))
        assertEquals("4.5 to 1 itself is the readable band", ReadingComfort.TIRING, band(ReadingContrast.AA))
        assertEquals("just below 4.5 to 1 is the band the sheet refuses", ReadingComfort.FAINT, band(4.49))
    }

    @Test
    fun `the extremes of the scale land in the outer bands`() {
        assertEquals("the worst possible pairing is refused", ReadingComfort.FAINT, band(1.0))
        assertEquals("black on white is the comfortable band", ReadingComfort.EASY, band(21.0))
    }

    // endregion

    // region What a reader is told

    @Test
    fun `a pairing the sheet accepts is never described as too faint`() {
        SUGGESTED_BACKGROUNDS.forEach { hex ->
            val palette = ReaderPalette.derived("", hex)
            assertTrue("$hex is offered, so it must be usable", palette.isReadable)
            assertNotEquals(
                "$hex was offered and then called too faint",
                ReadingComfort.FAINT,
                band(palette.contrast),
            )
        }
    }

    @Test
    fun `a refused pairing is the faint band`() {
        val refused = ReaderPalette("", "#FFFFFF", "#EEEEEE")
        assertTrue("near-white on white is below the floor", !refused.isReadable)
        assertEquals("a refused pairing is the faint band", ReadingComfort.FAINT, band(refused.contrast))
    }

    // endregion

    // region Four languages

    @Test
    fun `the bands and the measured ratio are stated in English`() = assertTheSheetSpeaks()

    @Test
    @Config(qualifiers = "fr-rFR")
    fun `the bands and the measured ratio are stated in French`() = assertTheSheetSpeaks()

    @Test
    @Config(qualifiers = "de-rDE")
    fun `the bands and the measured ratio are stated in German`() = assertTheSheetSpeaks()

    @Test
    @Config(qualifiers = "es-rES")
    fun `the bands and the measured ratio are stated in Spanish`() = assertTheSheetSpeaks()

    // endregion

    private fun band(ratio: Double) = ReadingComfort.band(ratio)

    private fun assertTheSheetSpeaks() {
        // Robolectric's own application, because `androidx.test.core` is not on this
        // module's unit-test classpath and one sentence is not worth a dependency.
        val context = RuntimeEnvironment.getApplication()

        val said = ReadingComfort.entries.map { context.getString(it.label) }
        said.forEach { assertTrue("a band resolved to nothing: $said", it.isNotBlank()) }
        assertEquals("two bands read the same: $said", said.size, said.toSet().size)

        val ratio = context.getString(R.string.theme_page_colour_ratio, MEASURED)
        assertTrue("the ratio line dropped its measurement: $ratio", ratio.contains(MEASURED))

        val refusal = context.getString(R.string.theme_page_colour_refused, MEASURED, FLOOR)
        assertTrue("the refusal dropped the ratio it measured: $refusal", refusal.contains(MEASURED))
        assertTrue("the refusal dropped the floor it refused against: $refusal", refusal.contains(FLOOR))
    }

    private companion object {
        const val MEASURED = "3.2"
        const val FLOOR = "4.5"
    }
}
