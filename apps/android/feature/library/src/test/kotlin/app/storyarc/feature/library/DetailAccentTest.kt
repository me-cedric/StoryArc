package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.ui.graphics.Color
import app.storyarc.core.model.CoverAccent
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.ReadingContrast
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The bridge between the extractor's answer and the page's colours.
 *
 * `CoverAccent` is already tested case for case, and mirrored on iOS. What is untested
 * until here is the crossing: a `#rrggbb` becoming a Compose colour. A silent failure in
 * that step would draw every page black and read as a colour bug rather than a parsing one.
 *
 * **And the four cases task 1.3 names, answered here the same way iOS answers them** in
 * `Tests/LibraryFeatureTests/DetailWashTests.swift`: a colour that clears the floor, one
 * that has to be adjusted to clear it, a monochrome cover that yields nothing, and a cover
 * that never decoded. The two files reach those answers through different arithmetic — see
 * [aColourThatCannotBeUsedRawIsAdjustedUntilItClearsTheFloor] for why Android has no
 * `DetailWash` — and that is exactly why they have to assert the same answers.
 *
 * Robolectric, and `GraphicsMode.NATIVE`, for one case only: [aRealCoverComesBackAsTheGrid]
 * needs a real `Bitmap`. The rest are pure and would run without it.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34])
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
    fun aCoverThatNeverDecodedYieldsNothing() {
        // The fourth of task 1.3's named cases, and the one neither platform tested until
        // now. It is asserted at the census rather than at the bitmap because that is the
        // only shape the app can actually be in: a cover that cannot be decoded reaches the
        // page as no image at all -- `rememberDetailAccent` is handed null and never asks
        // the extractor, exactly as iOS's `derivedWash()` guards on `let cover` before it
        // calls `CoverAccent.pixels`. `CoverAccent.pixels`'s own `width <= 0` guard is
        // defensive and unreachable through `Bitmap.createBitmap`, which refuses a zero
        // dimension outright.
        //
        // iOS asserts the same answer from the same shape, `DetailWash.of(cover: [])`.
        assertNull(CoverAccent.derived(IntArray(0)))
    }

    @Test
    fun aRealCoverComesBackAsTheGrid() {
        // iOS's `samplesToTheGrid`, which `CoverAccent.kt` records as "the one part of this
        // file no JVM unit test reaches". That was true of a plain JVM test and is not true
        // of a Robolectric one, so the extractor suites are mirrored case for case again
        // rather than thirteen against fourteen.
        val cover = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
        cover.eraseColor(0xFFDC143C.toInt())

        val pixels = CoverAccent.pixels(cover)

        assertEquals(CoverAccent.SAMPLE_EDGE * CoverAccent.SAMPLE_EDGE, pixels.size)
        assertEquals("#DC143C", CoverAccent.dominant(pixels))
    }

    @Test
    fun aColourThatCannotBeUsedRawIsAdjustedUntilItClearsTheFloor() {
        // The second of task 1.3's named cases. A near-black cover is already dark enough to
        // carry white, so the wash is the cover's own colour -- and an accent drawn on it in
        // that same colour would be invisible. `legible` has to move it before anything is
        // drawn, and what it moved it to still has to clear the floor.
        //
        // **This is where Android's answer stops mirroring iOS's arithmetic, deliberately.**
        // iOS walks a second adjustment -- a blend strength stepped down until *body text*
        // over the washed canvas clears 4.5:1 -- because iOS's wash is the page's background
        // with running text on it. Android's wash is a container: `DetailHero`'s `Surface`,
        // carrying the cover in its own `surfaceSunken` well and the filled action, and no
        // text at all. The title and the series ride the app bar. So a `DetailWash` here
        // would walk a blend against a text colour this page never draws on that surface,
        // and `CoverAccent.wash` already darkens until white clears AA, which is the pair
        // Android actually draws. Same answers, different composition -- ADR-0001's case.
        val nearBlack = IntArray(CoverAccent.SAMPLE_EDGE * CoverAccent.SAMPLE_EDGE) { 0x101838 }

        val colours = requireNotNull(CoverAccent.derived(nearBlack))

        assertEquals("#101838", CoverAccent.dominant(nearBlack))
        assertNotEquals(
            "the raw colour was used as it came out of the image",
            "#101838",
            colours.accent,
        )
        val ratio = ReadingContrast.ratio(colours.accent, colours.wash)
        assertTrue("$ratio should clear ${CoverAccent.FLOOR}", ratio >= CoverAccent.FLOOR)
        // And what is written on the accent clears its own floor, which is the other pair a
        // reader sees: the primary action's label.
        assertTrue(
            "the action's own label is illegible on it",
            ReadingContrast.ratio(colours.onAccent, colours.accent) >= ReadingContrast.AA,
        )
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
