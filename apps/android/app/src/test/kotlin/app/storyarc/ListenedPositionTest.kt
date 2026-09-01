package app.storyarc

import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Turning where the audio is into where the reader is.
 *
 * The player says "42 seconds into part 2 of 5"; the library, the shelves and the merge all
 * speak [ReadingPosition]. This is the one place the two meet, and it is a pure function so
 * that the interesting half — what counts as finished, and what happens when nobody knows
 * how long a part is — can be asserted without a decoder.
 *
 * `reading-progress`:
 *
 * > **WHEN** a listener reaches the end of an audiobook … **THEN** the publication is marked
 * > finished by the same rule that marks a comic finished on its last page
 */
class ListenedPositionTest {

    private val known = listOf(
        PlaybackPart("One", PlaybackDuration.Known(300_000)),
        PlaybackPart("Two", PlaybackDuration.Known(300_000)),
    )

    private val spoken = listOf(
        PlaybackPart("One", PlaybackDuration.Estimated(300_000)),
        PlaybackPart("Two", PlaybackDuration.Estimated(300_000)),
    )

    @Test
    fun `a position carries its part, its offset and its part's length`() {
        val position = ListenedPosition.of(PlaybackPosition(1, 42_000), known)

        assertEquals(ReadingPosition.Listening(1, 2, 42_000, 300_000), position)
    }

    /**
     * An estimated length is not a length.
     *
     * `PlaybackDuration.Estimated` answers `statedMillis` with null precisely so an estimate
     * is never presented as exact, and this carries that absence into the store rather than
     * quietly taking `estimatedMillis` on the way past.
     */
    @Test
    fun `an estimated part length is stored as no length at all`() {
        val position = ListenedPosition.of(PlaybackPosition(1, 42_000), spoken)

        assertNull((position as ReadingPosition.Listening).ofMillis)
    }

    @Test
    fun `a part the player does not have is still a position`() {
        val position = ListenedPosition.of(PlaybackPosition(7, 1_000), known)

        assertEquals(ReadingPosition.Listening(7, 2, 1_000, null), position)
    }

    // MARK: finishing by listening

    @Test
    fun `the end of the last part finishes the publication`() {
        assertTrue(ListenedPosition.isFinished(PlaybackPosition(1, 300_000), known))
    }

    @Test
    fun `the start of the last part does not`() {
        assertFalse(ListenedPosition.isFinished(PlaybackPosition(1, 0), known))
    }

    @Test
    fun `the end of an earlier part does not`() {
        assertFalse(ListenedPosition.isFinished(PlaybackPosition(0, 300_000), known))
    }

    /**
     * A source with no true duration cannot report the end this way, and does not pretend to.
     *
     * The fraction of a listening position with no length stops at the last part's index
     * over the part count, so it never reaches the end — which is the honest answer, and why
     * read-aloud marks itself finished from the reader's own progression instead.
     */
    @Test
    fun `a session with no known duration never claims the end`() {
        assertFalse(ListenedPosition.isFinished(PlaybackPosition(1, 999_000), spoken))
    }

    @Test
    fun `a publication with no parts is not finished`() {
        assertFalse(ListenedPosition.isFinished(PlaybackPosition(0, 0), emptyList()))
    }

    // MARK: coming back

    @Test
    fun `a stored listening position is where the audio starts again`() {
        val stored = ReadingPosition.Listening(2, 5, 42_000, 300_000)

        assertEquals(PlaybackPosition(2, 42_000), ListenedPosition.resume(stored, false))
    }

    /**
     * A finished book starts at the beginning.
     *
     * The readers already do this — `ReaderViewModel` takes the recorded position
     * `takeUnless { record.isFinished }` — and a listener reopening a book they finished
     * means to hear it, not to hear the last four seconds of it.
     */
    @Test
    fun `a finished publication starts at the beginning`() {
        val stored = ReadingPosition.Listening(4, 5, 299_000, 300_000)

        assertNull(ListenedPosition.resume(stored, true))
    }

    /**
     * `reading-progress`: "there is one position … so returning never offers a choice of
     * two".
     *
     * The one position a publication has may be a page or a place in the text, and neither
     * is somewhere audio can start. Null, so the book opens at its beginning — never a
     * second stored place, and never a prompt.
     */
    @Test
    fun `a position left by reading is not a place to start playing`() {
        assertNull(ListenedPosition.resume(ReadingPosition.Page(3, 20), false))
        assertNull(ListenedPosition.resume(ReadingPosition.Reflowable(0.4, "{}"), false))
    }
}
