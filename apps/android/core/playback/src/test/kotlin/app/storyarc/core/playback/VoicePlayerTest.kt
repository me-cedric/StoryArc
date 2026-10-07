package app.storyarc.core.playback

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The voice as a media3 `Player`: what the shade, the lock screen and a car read and press.
 *
 * Task 13.2. `ebook-reader`: the platform media controls "show the publication title and offer
 * play, pause, and sentence skip", and the second line names the chapter being spoken. The
 * voice used to draw these in a notification of its own; [VoicePlayer] now states them to the
 * player's one media session, and every press goes through [PlaybackCentre].
 *
 * The sentence skip itself is the session's custom command and `PlaybackServiceVoiceTest`
 * presses it. Robolectric for the main looper a `SimpleBasePlayer` runs on.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class VoicePlayerTest {

    private class Voice : PlayerSource {
        override val publicationId = "sea-room"
        override val title = "Sea Room"
        override val parts = listOf(PlaybackPart("One"), PlaybackPart("Two"), PlaybackPart("Three"))
        override var position = PlaybackPosition(1, 0)
        override val skipUnit = SkipUnit.SENTENCE
        override val detail = "Chapter Two"
        var state = PlaybackSession().started()
        override val session: PlaybackSession get() = state
        override val speed = PlaybackSpeed.NORMAL
        override var onChange: (() -> Unit)? = null
        override var onInterruptionEnd: ((mayResume: Boolean) -> Unit)? = null
        var stops = 0
        override fun play() { state = state.started(); onChange?.invoke() }
        override fun pause() { state = state.pausedByListener(); onChange?.invoke() }
        override fun stop() { stops += 1; state = state.stopped(); onChange?.invoke() }
        override fun seek(to: PlaybackPosition) { position = to; onChange?.invoke() }
        override fun setSpeed(speed: PlaybackSpeed) = Unit
    }

    private val voice = Voice()
    private val centre = PlaybackCentre()
    private val player = VoicePlayer(centre, reopen = null).also { player ->
        centre.onChange = { player.changed() }
        centre.start(voice)
    }

    @Test
    fun `the shade names the publication and the chapter being spoken`() {
        assertEquals("Sea Room", player.mediaMetadata.title)
        assertEquals("Chapter Two", player.mediaMetadata.artist)
        assertEquals(1, player.currentMediaItemIndex)
    }

    @Test
    fun `the shade's pause and play reach the voice`() {
        player.pause()

        assertFalse("the voice did not pause", voice.session.isPlaying)
        assertFalse(player.isPlaying)

        player.play()

        assertTrue("the voice did not play again", voice.session.isPlaying)
        assertTrue(player.isPlaying)
    }

    /** A car's next-track control moves a chapter, as it does for an audiobook (task 12.3). */
    @Test
    fun `a car's next track moves the voice to the next chapter`() {
        player.seekToNext()

        assertEquals(PlaybackPosition(2, 0), voice.position)
        assertEquals(2, player.currentMediaItemIndex)
    }

    @Test
    fun `a stop from a controller ends the session`() {
        player.stop()

        assertEquals(1, voice.stops)
        assertNull(centre.nowPlaying)
        assertEquals(0, player.mediaItemCount)
    }

    /**
     * The app's own controller drives a narrated file, never the voice. A stop it sent to the
     * file just before the voice displaced it arrives after the voice is seated, and must not
     * end the voice that has just started.
     */
    @Test
    fun `a stale command from the app's own controller does not reach the voice`() {
        player.fromTheApp = { true }

        player.stop()
        player.pause()

        assertEquals(0, voice.stops)
        assertTrue("the voice was paused by a command meant for the file", voice.session.isPlaying)
    }

    /** `audio-playback`: a control that cannot work is absent. A voice has no clock to seek. */
    @Test
    fun `no seek by time is offered for a voice`() {
        assertFalse(player.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM))
        assertFalse(player.isCommandAvailable(Player.COMMAND_SEEK_BACK))
        assertFalse(player.isCommandAvailable(Player.COMMAND_SEEK_FORWARD))
        assertTrue(player.isCommandAvailable(Player.COMMAND_PLAY_PAUSE))
    }
}
