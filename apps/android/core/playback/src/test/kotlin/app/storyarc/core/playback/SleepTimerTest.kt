package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Stopping a book for a listener who is falling asleep.
 *
 * `audio-playback`, *Sleep timer*:
 *
 * > **THEN** a duration or *end of chapter* may be chosen, the remaining time is shown on
 * > the player, and playback fades out rather than cutting off when it elapses
 * > **AND** the position at which it stopped is recorded, so resuming starts a little
 * > before it rather than where the fade ended
 *
 * All four clauses are here except the recording, which is `PlaybackHost`'s: it is the
 * rewind that turns "a little before" into a number, and it is asserted through the seek
 * the host makes rather than through this value.
 */
class SleepTimerTest {

    private fun playing(
        offsetMillis: Long = 0,
        partDuration: PlaybackDuration = PlaybackDuration.Known(600_000),
    ) = NowPlaying(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(PlaybackPart("One", partDuration)),
        partIndex = 0,
        offsetMillis = offsetMillis,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.NORMAL,
    )

    // MARK: a duration

    @Test
    fun `a chosen duration starts counting from itself`() {
        val timer = SleepTimer.of(SleepAfter.Duration(15 * 60_000L), playing())

        assertEquals(900_000L, timer?.remainingMillis)
    }

    @Test
    fun `time passing takes it down`() {
        val timer = SleepTimer(SleepAfter.Duration(900_000), 900_000)

        assertEquals(899_000, timer.ticked(1_000, playing()).remainingMillis)
    }

    @Test
    fun `it stops at nothing left rather than going negative`() {
        val timer = SleepTimer(SleepAfter.Duration(900_000), 500)

        val elapsed = timer.ticked(1_000, playing())
        assertEquals(0, elapsed.remainingMillis)
        assertTrue(elapsed.hasElapsed)
    }

    @Test
    fun `a duration of nothing is not a timer`() {
        assertNull(SleepTimer.of(SleepAfter.Duration(0), playing()))
    }

    // MARK: end of chapter

    @Test
    fun `end of chapter is what is left of the part being played`() {
        val timer = SleepTimer.of(SleepAfter.EndOfChapter, playing(offsetMillis = 120_000))

        assertEquals(480_000L, timer?.remainingMillis)
    }

    /**
     * A listener who skips forward has moved the end nearer.
     *
     * Re-read rather than counted down, because a timer keeping its own count would stop
     * them somewhere in the *next* chapter — which is the one thing choosing end of chapter
     * asks not to happen.
     */
    @Test
    fun `skipping forward inside the chapter brings the end nearer`() {
        val timer = SleepTimer(SleepAfter.EndOfChapter, 480_000)

        val after = timer.ticked(1_000, playing(offsetMillis = 500_000))
        assertEquals(100_000, after.remainingMillis)
    }

    /**
     * `audio-playback`: "every control the player offers works, or is absent — none is
     * present and refusing".
     *
     * A publication being read aloud has no true duration, so there is no end of chapter to
     * stop at, and the option is absent rather than doing nothing.
     */
    @Test
    fun `end of chapter is not offered where nothing knows how long the chapter is`() {
        assertNull(SleepTimer.of(SleepAfter.EndOfChapter, playing(partDuration = PlaybackDuration.Unknown)))
        assertNull(
            SleepTimer.of(
                SleepAfter.EndOfChapter,
                playing(partDuration = PlaybackDuration.Estimated(600_000)),
            ),
        )
        assertNull(SleepTimer.of(SleepAfter.EndOfChapter, null))
    }

    @Test
    fun `a duration is still offered where nothing knows how long the chapter is`() {
        assertNotNull(
            SleepTimer.of(
                SleepAfter.Duration(900_000),
                playing(partDuration = PlaybackDuration.Estimated(600_000)),
            ),
        )
    }

    // MARK: the fade

    @Test
    fun `the audio is at full volume until the fade begins`() {
        assertEquals(1f, SleepTimer(SleepAfter.Duration(900_000), 900_000).gain, 0f)
        assertEquals(1f, SleepTimer(SleepAfter.Duration(900_000), SleepTimer.FADE_MILLIS).gain, 0f)
    }

    @Test
    fun `it fades rather than cutting off`() {
        val half = SleepTimer(SleepAfter.Duration(900_000), SleepTimer.FADE_MILLIS / 2)

        assertEquals(0.5f, half.gain, 0.01f)
        assertFalse("half way through the fade is not silence", half.gain == 0f)
    }

    @Test
    fun `it is silent when it has elapsed`() {
        assertEquals(0f, SleepTimer(SleepAfter.Duration(900_000), 0).gain, 0f)
    }
}
