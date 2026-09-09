package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * How much of the chapter in progress is left, and whether that number moves.
 *
 * `audio-playback`, *Chapters*: the chapter in progress "states how much of itself is left,
 * so a listener can tell a chapter they have just begun from one they are about to finish".
 * Both chapter lists read [NowPlaying.leftInPartMillis] for it, and the sleep timer's *end
 * of chapter* asks the same question of the same property.
 *
 * **The number would freeze without a republish.** [PlaybackCentre] rebuilds the surface
 * when the player raises a callback, and media3 raises one for a seek, a transition and a
 * pause — never for the clock running on. So `reach` below moves the player without letting
 * it report, exactly as a running clock does not, and the last case is what the app's own
 * fifteen-second tick calls.
 *
 * Robolectric because a `MediaItem` reaches `Uri.parse`. Nothing here needs a decoder.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class RemainingChapterTimeTest {

    /** A folder of two files, so a part index and a part length mean something. */
    private fun book() = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = listOf(
            Audiobook.AudioPart("file:///sea-room-01.m4a", "The Harbour"),
            Audiobook.AudioPart("file:///sea-room-02.m4a", "The Crossing"),
        ),
    )

    /**
     * One file with a chapter list inside it, which is the shape most audiobooks arrive in.
     *
     * `Audiobook.layout` answers `MARKS` for a single source, and that branch is the one the
     * folder book above cannot reach: there `position` reports an offset inside its own file,
     * here it reports a time into the whole file.
     */
    private fun chapteredFile() = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = listOf(Audiobook.AudioPart("file:///sea-room.m4b", "Sea Room")),
    )

    /** A book playing, the way `PlaybackHost.start` starts one. */
    private fun started(player: FakePlayer, book: Audiobook = book()): PlaybackCentre {
        val centre = PlaybackCentre()
        val source = AudiobookSource(book, player)
        source.prepare()
        centre.start(source)
        return centre
    }

    /** A file measured, its marks announced, and the audio moved into the second chapter. */
    private fun insideTheSecondChapter(player: FakePlayer): PlaybackCentre {
        val centre = started(player, chapteredFile())
        player.measureFile(420_000)
        player.describeChapters(
            Triple("The Harbour", 0L, 120_000L),
            Triple("The Crossing", 120_000L, 420_000L),
        )
        centre.seek(PlaybackPosition(1, 300_000))
        return centre
    }

    @Test
    fun `the chapter in progress states how much of itself is left`() {
        val player = FakePlayer()
        val centre = started(player)
        // The decoder has read the playlist, so both files state a length.
        player.measure(120_000, 300_000)

        centre.seek(PlaybackPosition(1, 180_000))

        assertEquals(120_000L, centre.nowPlaying?.leftInPartMillis)
    }

    @Test
    fun `a chapter whose length nobody measured states no remainder`() {
        val player = FakePlayer()
        val centre = started(player)
        // A folder audiobook before a decoder has measured it. `publication-formats` opens
        // one without complaint, and an estimated remainder is a number a listener would
        // plan the next twenty minutes around.

        centre.seek(PlaybackPosition(0, 30_000))

        assertNull(centre.nowPlaying?.leftInPartMillis)
    }

    @Test
    fun `a remainder never runs past the end of its chapter`() {
        val player = FakePlayer()
        val centre = started(player)
        player.measure(120_000, 300_000)

        // A position recorded against a container that has since been re-read with shorter
        // parts. Zero left is honest; a negative clock reads as a chapter owing time.
        centre.seek(PlaybackPosition(0, 200_000))

        assertEquals(0L, centre.nowPlaying?.leftInPartMillis)
    }

    @Test
    fun `a refresh states where the audio reached, not where it last reported`() {
        val player = FakePlayer()
        val centre = started(player)
        player.measure(120_000, 300_000)
        player.reach(90_000)
        // Still the whole chapter, which is the defect: the surface holds the offset the
        // file started at for as long as that file plays. See `RecordedPositionTest`.
        assertEquals(120_000L, centre.nowPlaying?.leftInPartMillis)

        centre.refresh()

        assertEquals(30_000L, centre.nowPlaying?.leftInPartMillis)
    }

    /**
     * The delegation the app's tick actually calls.
     *
     * `PlayingBook` reaches the centre only through `PlaybackHost`, and on 2026-09-08 a
     * verifier replaced `PlaybackHost.refresh` with `= Unit` while every module still
     * reported BUILD SUCCESSFUL — a tick that has stopped refreshing, which is the defect
     * this change exists to remove. The grep in `AudioSurfacesAreWiredTest` guards the call
     * site; this guards what the call site reaches.
     */
    @Test
    fun `a refresh through the host reaches the centre`() {
        val player = FakePlayer()
        val source = AudiobookSource(book(), player)
        source.prepare()
        PlaybackHost.centre.start(source)
        try {
            player.measure(120_000, 300_000)
            player.reach(90_000)
            assertEquals(120_000L, PlaybackHost.nowPlaying.value?.leftInPartMillis)

            PlaybackHost.refresh()

            assertEquals(30_000L, PlaybackHost.nowPlaying.value?.leftInPartMillis)
        } finally {
            // The host is an object. A source left in it is the next test's source.
            PlaybackHost.stop()
        }
    }

    // MARK: one file with marks in it, where an offset is a time into the whole file

    @Test
    fun `a chapter inside one file states its own length left, not the file's`() {
        val player = FakePlayer()

        val centre = insideTheSecondChapter(player)

        assertEquals(1, centre.nowPlaying?.partIndex)
        assertEquals(120_000L, centre.nowPlaying?.leftInPartMillis)
    }

    /**
     * The scrub control's two ends, on the surface that used to mix them.
     *
     * `PlayerScreen.Position` ranges the slider over the chapter and hands what it reads back
     * to `seek`, so the offset it draws and the position it produces are the two halves of
     * one round trip. A slider ranged 0 to the chapter length, fed a file time, sits pinned
     * at its own end for every chapter after the first.
     */
    @Test
    fun `a scrub inside a chapter reads and writes the same place`() {
        val player = FakePlayer()

        val playing = insideTheSecondChapter(player).nowPlaying

        assertEquals(180_000L, playing?.offsetInPartMillis)
        assertEquals(PlaybackPosition(1, 150_000), playing?.positionInPart(30_000))
    }

    @Test
    fun `a chapter inside one file counts towards the whole book once`() {
        val player = FakePlayer()

        val centre = insideTheSecondChapter(player)

        assertEquals(300_000L, centre.nowPlaying?.elapsedTotalMillis)
    }

    /** *Sleep timer* asks the same question of the same value, so one repair answers both. */
    @Test
    fun `end of chapter inside one file ends at that chapter`() {
        val player = FakePlayer()
        val centre = insideTheSecondChapter(player)

        val timer = SleepTimer.of(SleepAfter.EndOfChapter, centre.nowPlaying)

        assertEquals(120_000L, timer?.remainingMillis)
    }
}
