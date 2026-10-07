package app.storyarc.core.playback

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What a book that ends on a failed part leaves behind for the screen it ends on.
 *
 * Task 2.5, owner answer O12. A failed last or only part ends the session, and by then
 * [PlaybackCentre.nowPlaying] is null and every part count that hung off it is gone. The
 * finished state of the player has to say how much could not be played, so the centre keeps the
 * count past the teardown and [PlaybackHost.ended] hands it on.
 *
 * Android's decoder cannot carry on after a fatal error: ExoPlayer is idle until it is
 * prepared again, and a single file has no later file to prepare. So the session ends at the
 * failure, as it did, and what changes is that the ending is remembered. iOS's player plays the
 * file out first; `PlayerLastFinishedTests` asserts its half.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class DamagedBookEndingTest {

    private fun file(vararg names: String) = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = names.map { Audiobook.AudioPart("file:///$it", it) },
    )

    private class Playing(book: Audiobook) {
        val player = FakePlayer()
        val source = AudiobookSource(book, player)
        val centre = PlaybackCentre()

        init {
            source.prepare()
            centre.start(source)
        }
    }

    @After
    fun quiet() = PlaybackHost.stop()

    @Test
    fun `a single file that fails ends the session and is remembered as one part lost`() {
        val playing = Playing(file("sea-room.m4b"))

        playing.player.fail()

        assertNull("the compact bar goes", playing.centre.nowPlaying)
        assertEquals(PlaybackCentre.Ending("sea-room", 1), playing.centre.lastEnding)
    }

    @Test
    fun `the last file of a folder that fails is remembered, and the one before it is not an ending`() {
        val playing = Playing(file("one.mp3", "two.mp3"))

        playing.player.fail()
        assertNotNull("a later file takes over, so nothing has ended", playing.centre.nowPlaying)
        assertNull(playing.centre.lastEnding)

        playing.player.reachPart(1, 0)
        playing.player.fail()

        assertNull(playing.centre.nowPlaying)
        assertEquals(PlaybackCentre.Ending("sea-room", 2), playing.centre.lastEnding)
    }

    @Test
    fun `a book that was whole states no loss when it ends`() {
        val playing = Playing(file("sea-room.m4b"))

        playing.centre.stop()

        assertEquals(PlaybackCentre.Ending("sea-room", 0), playing.centre.lastEnding)
    }

    @Test
    fun `a book already partial at the index states it when it ends`() {
        val playing = Playing(file("sea-room.m4b").copy(skippedPartCount = 2))

        playing.centre.stop()

        assertEquals(2, playing.centre.lastEnding?.unplayedParts)
    }

    @Test
    fun `starting the next book clears the last one's loss`() {
        val playing = Playing(file("sea-room.m4b"))
        playing.player.fail()
        assertNotNull(playing.centre.lastEnding)

        val next = AudiobookSource(
            Audiobook(
                id = "long-field",
                title = "The Long Field",
                sources = listOf(Audiobook.AudioPart("file:///lf.m4b", "lf")),
            ),
            FakePlayer(),
        )
        next.prepare()
        playing.centre.start(next)

        assertNull(playing.centre.lastEnding)
    }

    /** The host is what the screen reads, so it is asserted over the same ending. */
    @Test
    fun `the host hands the screen the loss once nothing is playing`() {
        val player = FakePlayer()
        val source = AudiobookSource(file("sea-room.m4b"), player)
        source.prepare()
        PlaybackHost.centre.start(source)
        assertNull(PlaybackHost.ended.value)

        player.fail()

        assertNull(PlaybackHost.nowPlaying.value)
        assertEquals(PlaybackCentre.Ending("sea-room", 1), PlaybackHost.ended.value)
    }
}
