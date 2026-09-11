package app.storyarc

import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
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

    /**
     * Ten chapters inside one file, which is the shape `PartLayout.MARKS` describes.
     *
     * The defect this pins was in `AudiobookSource`, not here: it reported a time into the
     * *file* as the offset into the chapter, so `fraction` divided a file time by a chapter
     * length, coerced the result to 1.0, and read `(part + 1) / partCount`. A listener who had
     * just started chapter ten was recorded as having finished the book. The source converts
     * now — `MarksPositionTest` drives a real one — and these are the two readers in this
     * module that the conversion protects.
     */
    private val chaptered = List(10) { index ->
        PlaybackPart("Chapter ${index + 1}", PlaybackDuration.Known(60_000))
    }

    @Test
    fun `a position inside a chapter is a fraction of the whole book`() {
        val position = ListenedPosition.of(PlaybackPosition(1, 30_000), chaptered)

        assertEquals(0.15, position.fraction, 0.0001)
    }

    @Test
    fun `the start of the last chapter of one file does not finish the book`() {
        assertFalse(ListenedPosition.isFinished(PlaybackPosition(9, 0), chaptered))
    }

    @Test
    fun `the end of the last chapter of one file finishes the book`() {
        assertTrue(ListenedPosition.isFinished(PlaybackPosition(9, 60_000), chaptered))
    }

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

    // MARK: what the publication's page marks, and in which unit

    /** Chapter lengths as the page lists them: two minutes, five, then four. */
    /**
     * A session playing a single chaptered file, which is the shape that used to state 0:00.
     *
     * `partStartMillis` is the second mark, and `offsetMillis` is a time into the whole file,
     * exactly as `AudiobookSource` reports one for `PartLayout.MARKS`.
     */
    private fun playing(publicationId: String = "sea-room") = NowPlaying(
        publicationId = publicationId,
        title = "Sea Room",
        parts = listOf(
            PlaybackPart("The Harbour", PlaybackDuration.Known(120_000)),
            PlaybackPart("The Crossing", PlaybackDuration.Known(300_000)),
        ),
        partIndex = 1,
        // Three minutes into the second chapter. `partStartMillis` is where that chapter
        // starts in the file, which only `PlaybackMemory` reads — see `NowPlaying`.
        offsetMillis = 180_000,
        partStartMillis = 120_000,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.NORMAL,
    )

    @Test
    fun `the session's own place is measured against its chapter`() {
        val place = ListenedPosition.placeOf("sea-room", playing(), saved = null)

        assertEquals(1, place.partIndex)
        assertEquals(180_000L, place.offsetInChapterMillis)
    }

    @Test
    fun `a session wins over what the store last wrote`() {
        val place = ListenedPosition.placeOf(
            publicationId = "sea-room",
            playing = playing(),
            saved = PlaybackPosition(0, 30_000),
        )

        assertEquals(1, place.partIndex)
        assertEquals(180_000L, place.offsetInChapterMillis)
    }

    @Test
    fun `another book's session marks nothing on this page`() {
        val place = ListenedPosition.placeOf(
            publicationId = "sea-room",
            playing = playing(publicationId = "the-peregrine"),
            saved = null,
        )

        assertNull(place.partIndex)
        assertEquals(0L, place.offsetInChapterMillis)
    }

    /**
     * The store keeps a seek target, which for one chaptered file is a whole-file time.
     *
     * Six minutes into the file is one minute into the second chapter, which starts at two.
     * Reading it as an offset into the chapter would state four minutes left of five when
     * one has passed.
     */
    /**
     * The store and the page now share a unit, so nothing is subtracted here.
     *
     * `PlaybackPosition.offsetMillis` is measured from the start of its part for every
     * layout. This case used to hand in a whole-file time and expect the earlier chapters'
     * lengths to be taken off it.
     */
    @Test
    fun `a stored offset is already inside its own chapter`() {
        val place = ListenedPosition.placeOf(
            publicationId = "sea-room",
            playing = null,
            saved = PlaybackPosition(1, 60_000),
        )

        assertEquals(1, place.partIndex)
        assertEquals(60_000L, place.offsetInChapterMillis)
    }

    @Test
    fun `a stored place in the first chapter is already inside it`() {
        val place = ListenedPosition.placeOf(
            publicationId = "sea-room",
            playing = null,
            saved = PlaybackPosition(0, 30_000),
        )

        assertEquals(0, place.partIndex)
        assertEquals(30_000L, place.offsetInChapterMillis)
    }

    /**
     * A folder audiobook nobody is playing states no chapter length, so nothing is subtracted.
     *
     * `ListenedChapters.of` reports `statedMillis = null` for every part of a folder without a
     * session, and there the stored offset is already inside its own file. Giving up on the
     * first unmeasured chapter is what keeps a part-relative offset from being reduced twice.
     */
    /**
     * A chapter nobody measured is still a place.
     *
     * This used to answer zero: the offset was a file time, and taking an unmeasured
     * chapter's length off it was impossible, so the page stated the chapter's start. One
     * unit removes the arithmetic and with it the case.
     */
    @Test
    fun `a place in an unmeasured chapter keeps its offset`() {
        val place = ListenedPosition.placeOf(
            publicationId = "sea-room",
            playing = null,
            saved = PlaybackPosition(1, 30_000),
        )

        assertEquals(1, place.partIndex)
        assertEquals(30_000L, place.offsetInChapterMillis)
    }

    @Test
    fun `a book nobody has started marks no chapter`() {
        val place = ListenedPosition.placeOf("sea-room", playing = null, saved = null)

        assertNull(place.partIndex)
        assertEquals(0L, place.offsetInChapterMillis)
    }
}
