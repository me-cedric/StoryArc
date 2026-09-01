package app.storyarc.core.playback

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What happens to a narrated book when something else takes the audio.
 *
 * `audio-playback`, *Something else takes the audio*:
 *
 * > **THEN** playback stops, and resumes by itself when the system says it may — but a
 * > pause the listener made is never undone this way
 * > **AND** audio taken for good ends the session and records the position rather than
 * > leaving it paused for ever
 *
 * **This is the half that was missing.** The shared table has said all of that since
 * `PlaybackSession` moved into this module, and read-aloud connects it through its own
 * focus listener — but nothing connected it on the audiobook path. media3 handles the
 * focus itself and reports the result as a plain `onIsPlayingChanged(false)`, which the
 * source read as *the listener paused*. So a call ended and the book stayed silent with
 * the pause attributed to a listener who never touched it, and a permanent loss left a
 * session paused for ever with no position written.
 *
 * The signals that separate the three cases are media3's own, and [PlaybackFocus] is the
 * one place they are read. iOS's `PlayerInterruptionTests` asserts the same three from
 * `AVAudioSession`'s notification instead.
 *
 * Robolectric because building a `MediaItem` from a URI string reaches `Uri.parse`, which
 * the unit-test JVM does not implement. Nothing here needs a decoder.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class PlayerInterruptionTest {

    private fun book() = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = listOf(Audiobook.AudioPart("file:///sea-room.m4b", "Sea Room")),
    )

    private class Started {
        val player = FakePlayer()
        val recorded = mutableListOf<Pair<String, PlaybackPosition>>()
        val centre = PlaybackCentre(
            record = { source, position -> recorded += source.publicationId to position },
        )
        lateinit var source: AudiobookSource
    }

    private fun playing(): Started = Started().apply {
        source = AudiobookSource(book(), player)
        source.prepare()
        centre.start(source)
    }

    // MARK: the audio is taken for a moment

    @Test
    fun `a call taken during a narrated book is not the listener pausing`() {
        val started = playing()

        started.player.suppress()

        assertEquals(PlaybackState.PAUSED, started.source.session.state)
        assertEquals(PauseCause.INTERRUPTION, started.source.session.pausedBy)
    }

    @Test
    fun `the call ending gives the audio back`() {
        val started = playing()
        started.player.suppress()

        started.player.unsuppress()

        assertEquals(PlaybackState.PLAYING, started.source.session.state)
        assertTrue(started.player.isPlaying)
    }

    /**
     * The rule the whole table exists for, on the path that did not enforce it.
     *
     * A listener who presses pause while a call is in progress has decided. media3 gives
     * the focus up at that point, so the suppression lifts on its own when the call ends —
     * and a session that still called that pause the interruption's would start a book
     * nobody asked to hear.
     */
    @Test
    fun `a pause the listener made during the call is not undone when it ends`() {
        val started = playing()
        started.player.suppress()

        started.source.pause()
        started.player.unsuppress()

        assertEquals(PlaybackState.PAUSED, started.source.session.state)
        assertEquals(PauseCause.LISTENER, started.source.session.pausedBy)
        assertTrue(!started.player.isPlaying)
    }

    // MARK: the audio is taken for good

    @Test
    fun `audio taken for good ends the session and records the position`() {
        val started = playing()
        started.player.reach(42_000)

        started.player.loseAudioForGood()

        assertEquals(listOf("sea-room" to PlaybackPosition(0, 42_000)), started.recorded)
        assertNull("the surface goes away rather than sitting paused", started.centre.nowPlaying)
    }

    /**
     * media3 gives up on a suppression that has lasted too long, with a reason of its own.
     *
     * The same outcome as a permanent loss: there is nothing left to wait for, and a
     * foreground service held open for a book nobody is hearing is what the spec forbids.
     */
    @Test
    fun `a suppression media3 gives up on ends the session too`() {
        val started = playing()
        started.player.suppress()

        started.player.loseAudioForGood(Player.PLAY_WHEN_READY_CHANGE_REASON_SUPPRESSED_TOO_LONG)

        assertEquals(1, started.recorded.size)
        assertNull(started.centre.nowPlaying)
    }

    // MARK: 3.9 — the route changes

    /**
     * `audio-playback`: headphones removed pauses, "and it does not resume by itself when
     * they are reconnected".
     *
     * media3's `setHandleAudioBecomingNoisy(true)` does the pausing and names its own
     * reason for it. What makes the second clause true is *which* pause this is recorded
     * as: the listener's, because nothing the platform sends afterwards undoes one of
     * those. iOS's `PlayerCentre.routeLost` uses the identical mechanism.
     */
    @Test
    fun `headphones removed pauses as the listener, so nothing gives it back`() {
        val started = playing()

        started.player.loseAudioForGood(Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY)

        assertEquals(PlaybackState.PAUSED, started.source.session.state)
        assertEquals(PauseCause.LISTENER, started.source.session.pausedBy)
        assertNotNull("the book is paused, not ended", started.centre.nowPlaying)
    }

    // MARK: what is not an interruption

    /**
     * Not every suppression is the audio being taken.
     *
     * media3 1.11.0 carries five suppression reasons and one of them —
     * `PLAYBACK_SUPPRESSION_REASON_SCRUBBING` — is the player's own doing while a listener
     * drags the scrub control. Reading that as a phone call would put the session in the
     * one state that resumes by itself the moment the drag ends.
     */
    @Test
    fun `a suppression the player made for itself is not an interruption`() {
        val started = playing()

        started.player.suppress(Player.PLAYBACK_SUPPRESSION_REASON_SCRUBBING)

        assertEquals(PlaybackState.PLAYING, started.source.session.state)
    }
}
