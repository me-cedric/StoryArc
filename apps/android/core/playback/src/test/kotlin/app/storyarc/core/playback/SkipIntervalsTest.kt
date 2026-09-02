package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * How far a skip goes, and what the control says it goes.
 *
 * `audio-playback`, *Skipping*: "the audio moves by a fixed interval the listener can
 * configure, and the interval is stated on the control itself".
 *
 * The defaults are a **product decision** recorded in `design.md` — 15 back, 30 forward —
 * and these cases pin them so a later edit has to argue with the plan rather than with a
 * number nobody remembers choosing.
 */
class SkipIntervalsTest {

    @Test
    fun `the defaults are fifteen back and thirty forward`() {
        assertEquals(15, SkipIntervals.DEFAULT.backSeconds)
        assertEquals(30, SkipIntervals.DEFAULT.forwardSeconds)
        assertEquals(15_000L, SkipIntervals.DEFAULT.millis(SkipDirection.BACK))
        assertEquals(30_000L, SkipIntervals.DEFAULT.millis(SkipDirection.FORWARD))
    }

    /**
     * The offered set is media3's, not ours.
     *
     * `CommandButton` draws a numbered glyph for exactly 5, 10, 15 and 30 seconds in each
     * direction — read off `media3-session-1.11.0.aar`'s own constants — so an interval
     * outside that set puts a lying number, or a bare arrow, in the notification. Offering
     * the four the platform can draw is the platform's answer rather than a fifth product
     * decision.
     */
    @Test
    fun `the offered intervals are the four the platform draws a glyph for`() {
        assertEquals(listOf(5, 10, 15, 30), SkipIntervals.OFFERED_SECONDS)
        assertTrue(SkipIntervals.DEFAULT.backSeconds in SkipIntervals.OFFERED_SECONDS)
        assertTrue(SkipIntervals.DEFAULT.forwardSeconds in SkipIntervals.OFFERED_SECONDS)
    }

    /** Clamped rather than rejected, as `PlaybackSpeed` is: a stored value still plays. */
    @Test
    fun `an interval outside the offered range is clamped rather than refused`() {
        assertEquals(5, SkipIntervals.of(backSeconds = 1, forwardSeconds = 90).backSeconds)
        assertEquals(30, SkipIntervals.of(backSeconds = 1, forwardSeconds = 90).forwardSeconds)
    }

    /** A value between two offered ones is kept: the range is what is enforced, not the set. */
    @Test
    fun `a value inside the range that nothing offers is kept`() {
        assertEquals(20, SkipIntervals.of(backSeconds = 20, forwardSeconds = 20).backSeconds)
    }

    @Test
    fun `the two directions are independent`() {
        val chosen = SkipIntervals.of(backSeconds = 10, forwardSeconds = 5)
        assertEquals(10_000L, chosen.millis(SkipDirection.BACK))
        assertEquals(5_000L, chosen.millis(SkipDirection.FORWARD))
    }
}
