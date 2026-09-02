package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Where a skip lands, in whole-book time.
 *
 * `audio-playback`, *Skipping*: "skipping past the start or the end of a chapter continues
 * into the neighbouring one rather than stopping at the boundary".
 *
 * **A mirror of iOS's `PlaybackTimelineTests`, case for case**, because the arithmetic is a
 * decision rather than a platform fact: which end clamps, what a part of unknown length
 * does to the sum, and where "past the end" is. The two apps draw none of the same pixels
 * and must land a skip in the same place.
 */
class PlaybackTimelineTest {

    /** Three five-minute chapters. */
    private val parts = List(3) { PlaybackPart("Chapter ${it + 1}", PlaybackDuration.Known(300_000)) }

    // MARK: whole-book time

    @Test
    fun `whole-book time sums the parts before the position`() {
        assertEquals(
            660_000L,
            PlaybackTimeline.bookTimeOf(parts, PlaybackPosition(partIndex = 2, offsetMillis = 60_000)),
        )
    }

    /**
     * A part before the position with no length makes the sum unanswerable.
     *
     * Null rather than a guess: treating an unmeasured chapter as zero would put the
     * listener in the wrong chapter, which is worse than not moving.
     */
    @Test
    fun `a part before the position with no length has no whole-book time`() {
        val unmeasured = listOf(PlaybackPart("One"), parts[1], parts[2])
        assertNull(PlaybackTimeline.bookTimeOf(unmeasured, PlaybackPosition(2, 60_000)))
    }

    @Test
    fun `a part that is not in this book has no whole-book time`() {
        assertNull(PlaybackTimeline.bookTimeOf(parts, PlaybackPosition(7, 0)))
    }

    /** An estimate is not a total, and `audio-playback` forbids presenting one as one. */
    @Test
    fun `an estimated length is not counted as a length`() {
        val estimated = listOf(PlaybackPart("One", PlaybackDuration.Estimated(300_000)), parts[1])
        assertNull(PlaybackTimeline.bookTimeOf(estimated, PlaybackPosition(1, 0)))
    }

    // MARK: the place a whole-book time names

    @Test
    fun `a whole-book time finds the part it falls in`() {
        assertEquals(
            PlaybackPosition(1, 30_000),
            PlaybackTimeline.positionAt(parts, 330_000),
        )
    }

    @Test
    fun `a whole-book time past the end is the end of the last part`() {
        assertEquals(
            PlaybackPosition(2, 300_000),
            PlaybackTimeline.positionAt(parts, 5_000_000),
        )
    }

    @Test
    fun `a part with no length is as far as the arithmetic honestly reaches`() {
        val unmeasured = listOf(parts[0], PlaybackPart("Two"), parts[2])
        assertEquals(
            PlaybackPosition(1, 90_000),
            PlaybackTimeline.positionAt(unmeasured, 390_000),
        )
    }

    @Test
    fun `a book with no parts names no place`() {
        assertNull(PlaybackTimeline.positionAt(emptyList(), 1_000))
    }

    // MARK: skipping

    @Test
    fun `skipping back across a part boundary continues into the previous part`() {
        assertEquals(
            PlaybackPosition(0, 295_000),
            PlaybackTimeline.skip(parts, PlaybackPosition(1, 5_000), byMillis = -10_000),
        )
    }

    @Test
    fun `skipping forward across a part boundary continues into the next part`() {
        assertEquals(
            PlaybackPosition(1, 10_000),
            PlaybackTimeline.skip(parts, PlaybackPosition(0, 280_000), byMillis = 30_000),
        )
    }

    @Test
    fun `skipping back from the start stops at the start`() {
        assertEquals(
            PlaybackPosition(0, 0),
            PlaybackTimeline.skip(parts, PlaybackPosition(0, 4_000), byMillis = -15_000),
        )
    }

    @Test
    fun `skipping forward past the end lands at the end of the last part`() {
        assertEquals(
            PlaybackPosition(2, 300_000),
            PlaybackTimeline.skip(parts, PlaybackPosition(2, 290_000), byMillis = 30_000),
        )
    }

    @Test
    fun `a skip that stays inside the part stays inside the part`() {
        assertEquals(
            PlaybackPosition(1, 100_000),
            PlaybackTimeline.skip(parts, PlaybackPosition(1, 130_000), byMillis = -30_000),
        )
    }

    /**
     * Nothing moves rather than something wrong.
     *
     * The one case where the boundary rule cannot be honoured is a book whose earlier parts
     * have no measured length — a folder the decoder has not read yet. Answering null leaves
     * the caller free to do nothing, which is what `AudiobookSource` does.
     */
    @Test
    fun `a skip through unmeasured parts answers nothing rather than a wrong place`() {
        val unmeasured = listOf(PlaybackPart("One"), parts[1])
        assertNull(PlaybackTimeline.skip(unmeasured, PlaybackPosition(1, 5_000), byMillis = -10_000))
    }
}
