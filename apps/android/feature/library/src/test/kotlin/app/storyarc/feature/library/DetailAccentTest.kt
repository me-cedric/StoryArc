package app.storyarc.feature.library

import androidx.compose.ui.graphics.Color
import app.storyarc.core.model.CoverAccent
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.ReadingContrast
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The bridge between the extractor's answer and the page's colours.
 *
 * `CoverAccent` is already tested case for case, and mirrored on iOS. What is untested
 * until here is the crossing: a `#rrggbb` becoming a Compose colour. A silent failure in
 * that step would draw every page black and read as a colour bug rather than a parsing one.
 */
class DetailAccentTest {

    @Test
    fun aSixDigitHexBecomesAnOpaqueColour() {
        assertEquals(Color(0xFFEC7C27), parseHex("#EC7C27"))
    }

    @Test
    fun theHashIsOptionalAndTheAlphaIsNeverTransparent() {
        // The wash sits behind text. A colour that arrived transparent would be legible in
        // the test and invisible on the device.
        val colour = parseHex("000000")

        assertEquals(Color(0xFF000000), colour)
        assertEquals(1f, colour?.alpha)
    }

    @Test
    fun anythingThatIsNotSixHexDigitsIsRefused() {
        // Refused rather than defaulted: a default here is a page drawn in a colour no cover
        // produced, which is exactly what "never used raw" is guarding against.
        assertNull(parseHex("#FFF"))
        assertNull(parseHex("#GGGGGG"))
        assertNull(parseHex(""))
    }

    @Test
    fun theWholeAnswerCrossesIntact() {
        val colours = CoverColours(wash = "#101010", accent = "#EC7C27", onAccent = "#000000")

        val accent = detailAccentOf(colours)

        assertNotNull(accent)
        assertEquals(Color(0xFF101010), accent?.wash)
        assertEquals(Color(0xFFEC7C27), accent?.accent)
        assertEquals(Color(0xFF000000), accent?.onAccent)
    }

    @Test
    fun aMonochromeCoverYieldsNothingRatherThanAMuddyWash() {
        // The manga case, and the commonest one. The page falls back to the app's own accent
        // instead of tinting every black-and-white book the same sepia.
        val greys = IntArray(CoverAccent.SAMPLE_EDGE * CoverAccent.SAMPLE_EDGE) { 0x808080 }

        assertNull(CoverAccent.derived(greys))
    }

    @Test
    fun aDerivedAccentClearsTheFloorAgainstTheWashItIsDrawnOn() {
        // The pair the button relies on. The delta forbids the raw colour and requires the
        // adjusted one, and this is the property that makes drawing the action inside the
        // hero safe rather than merely tidy.
        val red = IntArray(CoverAccent.SAMPLE_EDGE * CoverAccent.SAMPLE_EDGE) { 0xD01010 }

        val colours = CoverAccent.derived(red)

        assertNotNull(colours)
        val ratio = ReadingContrast.ratio(colours!!.accent, colours.wash)
        assertTrue("$ratio should clear ${CoverAccent.FLOOR}", ratio >= CoverAccent.FLOOR)
    }
}
