package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The cover-derived accent, case for case with iOS's `CoverAccentTests`.
 *
 * The pair exists for the reason the `PageOrdering` pair does: the two platforms have
 * to give one book one colour, and only two suites asserting the same cases can say so.
 */
class CoverAccentTest {
    /** A block of one colour, as the sampler would hand it over. */
    private fun block(pixel: Int, count: Int = 1024) = IntArray(count) { pixel }

    @Test
    fun `a cover of one colour is that colour`() {
        assertEquals("#DC143C", CoverAccent.dominant(block(0xDC143C)))
    }

    @Test
    fun `a greyscale cover has no accent at all`() {
        // A manga cover: ink, paper, and the greys between them. Deriving an accent
        // from these would tint every black-and-white book the same muddy nothing.
        val ramp = IntArray(1024) { step ->
            val level = step % 256
            (level shl 16) or (level shl 8) or level
        }

        assertNull(CoverAccent.dominant(ramp))
    }

    @Test
    fun `nothing to count is no accent, not a crash`() {
        assertNull(CoverAccent.dominant(IntArray(0)))
    }

    @Test
    fun `a mostly white cover still yields the colour it does carry`() {
        // Three quarters paper, one quarter sky. The paper abstains, so the sky wins —
        // which is the whole point of ignoring near-white.
        val pixels = block(0xFFFFFF, count = 768) + block(0x2E5AAC, count = 256)

        assertEquals("#2E5AAC", CoverAccent.dominant(pixels))
    }

    @Test
    fun `a colour on a tenth of the cover is a logo, not an accent`() {
        val pixels = block(0xFFFFFF, count = 1000) + block(0x2E5AAC, count = 24)

        assertNull(CoverAccent.dominant(pixels))
    }

    @Test
    fun `alpha in the high bits is ignored rather than counted`() {
        assertEquals("#DC143C", CoverAccent.dominant(block(0xFFDC143C.toInt())))
    }

    @Test
    fun `a dark accent on a dark wash is lightened until it clears the floor`() {
        val adjusted = requireNotNull(CoverAccent.legible("#101820", "#0A0A0A"))

        assertTrue(ReadingContrast.ratio(adjusted, "#0A0A0A") >= CoverAccent.FLOOR)
        assertNotEquals("#101820", adjusted)
    }

    @Test
    fun `a colour that already clears the floor is left alone`() {
        assertEquals("#FFFFFF", CoverAccent.legible("#FFFFFF", "#000000"))
    }

    @Test
    fun `a floor no lightness can reach is refused rather than approximated`() {
        // Mid-grey has no colour at all that reaches 7:1 against it — white tops out
        // near 4, black near 5.3. Returning the nearest miss would be an accent that
        // fails the gate the whole exercise exists to pass.
        assertNull(CoverAccent.legible("#4488CC", "#7F7F7F", ReadingContrast.AAA))
    }

    @Test
    fun `a cover with no colour derives nothing, so the caller keeps the brand accent`() {
        assertNull(CoverAccent.derived(block(0x808080)))
    }

    @Test
    fun `what comes out of the accent path always clears the floor`() {
        // The dark navy a night-sky cover yields, on the wash such a cover produces.
        // Raw, the accent would sit on itself at a ratio of 1:1 — the case the
        // adjustment exists for.
        val derived = requireNotNull(CoverAccent.derived(block(0x0F1B3A)))

        assertTrue(ReadingContrast.ratio(derived.accent, derived.wash) >= CoverAccent.FLOOR)
        assertTrue(ReadingContrast.ratio(derived.wash, "#FFFFFF") >= ReadingContrast.AA)
        // And what is written on the accent is legible on it, which is the third pairing
        // this screen has and the one an eye is worst at judging.
        assertTrue(ReadingContrast.ratio(derived.onAccent, derived.accent) >= ReadingContrast.AA)
        assertNotEquals("#0F1B3A", derived.accent)
    }

    @Test
    fun `the wash is dark enough for the white text that sits on it`() {
        val wash = requireNotNull(CoverAccent.wash(block(0xF2D98C)))

        assertTrue(ReadingContrast.ratio(wash, "#FFFFFF") >= ReadingContrast.AA)
    }

    @Test
    fun `a cover with no colour has no wash either`() {
        assertNull(CoverAccent.wash(block(0x808080)))
    }
}
