package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The moment between the listener asking for audio and the first sound of it.
 *
 * **This is where the Android player lost its own session**, and the sweep of 2026-09-02
 * photographed the result: `android-player-full.png` says *"Nothing is playing."* beside
 * `android-player-session-playing.png`, which is the system's own control naming the book,
 * playing, owned by this app's process. The audio worked; the surface observed nothing, so
 * the full player, its chapter list, the speed slider and the sleep timer had no picture in
 * either sweep because the screen holding them never drew.
 *
 * The mechanism is one ordering. [PlaybackCentre.start] attaches its listener and *then*
 * asks the source to play; [AudiobookSource.play] asked the player first and marked its own
 * session started afterwards. A real player answers `play()` inside that call — a
 * `MediaController` masks the change and reports it before the request has even crossed to
 * the service — with `playWhenReady` true and `isPlaying` still false, because nothing has
 * buffered yet. [PlaybackFocus.silenced] correctly reads that as neither a pause nor a
 * start and leaves the session alone; the session was still `IDLE`; and
 * [PlaybackCentre.publish] reads an inactive session as *the book ran out*. So the centre
 * dropped the source it had just started, published null, and never heard from it again —
 * while the controller had already told the service to play.
 *
 * `audio-playback` requires the compact bar whenever "something is playing or paused" and
 * requires opening the player to "never restart, reload or reposition the audio". Both
 * failed on the same line. The assertions below are of the centre rather than of the
 * screen, because the screen is a `collectAsStateWithLifecycle` over exactly this value.
 *
 * Robolectric because a `MediaItem` reaches `Uri.parse`. Nothing here needs a decoder.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class PlayerStartTest {

    private fun book() = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = listOf(
            Audiobook.AudioPart("file:///sea-room-01.m4a", "One"),
            Audiobook.AudioPart("file:///sea-room-02.m4a", "Two"),
        ),
    )

    /**
     * A book started the way the app starts one, on a player that has to buffer first.
     *
     * The order is `PlaybackHost.start`'s: prepare, then hand the source to the centre.
     */
    private fun started(player: FakePlayer): PlaybackCentre {
        val centre = PlaybackCentre()
        val source = AudiobookSource(book(), player)
        source.prepare()
        centre.start(source)
        return centre
    }

    @Test
    fun `a book whose first sound has not arrived is still what is playing`() {
        val centre = started(FakePlayer(soundsImmediately = false))

        // The screen's own condition, and the compact bar's: null is "nothing is playing".
        assertNotNull(centre.nowPlaying)
        assertEquals("Sea Room", centre.nowPlaying?.title)
        assertEquals("sea-room", centre.playingId)
    }

    @Test
    fun `a book still buffering reads as playing rather than as paused`() {
        val centre = started(FakePlayer(soundsImmediately = false))

        // Buffering is not a pause. A transport drawn from this must not offer play for a
        // book the listener has just started, and `isActive` is what keeps the bar up.
        val playing = requireNotNull(centre.nowPlaying)
        assertTrue(playing.isPlaying)
        assertTrue(playing.isActive)
    }

    @Test
    fun `the first sound arriving changes nothing the surface can see`() {
        val player = FakePlayer(soundsImmediately = false)
        val centre = started(player)
        val whileBuffering = centre.nowPlaying

        player.sound()

        assertEquals(whileBuffering, centre.nowPlaying)
    }

    @Test
    fun `starting a book records no position for it`() {
        // The drop wrote one: `publish` records the outgoing position before it lets a
        // source go, so a book that had played nothing wrote offset zero over whatever the
        // listener had reached. Starting is not an ending, and nothing is written here.
        val recorded = mutableListOf<Pair<String, PlaybackPosition>>()
        val centre = PlaybackCentre(record = { source, at -> recorded += source.publicationId to at })
        val source = AudiobookSource(book(), FakePlayer(soundsImmediately = false))
        source.prepare()
        centre.start(source)

        assertEquals(emptyList<Pair<String, PlaybackPosition>>(), recorded)
    }

    @Test
    fun `a listener pausing a book that never made a sound is still the listener's pause`() {
        // The other half of the same window: the session has to be *started* before the
        // player is asked, without that start swallowing what happens next.
        val player = FakePlayer(soundsImmediately = false)
        val centre = started(player)

        centre.toggle()

        assertEquals(PlaybackState.PAUSED, centre.nowPlaying?.session?.state)
        assertEquals(PauseCause.LISTENER, centre.nowPlaying?.session?.pausedBy)
    }
}
