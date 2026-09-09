package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * When a listening position is written, and what it is read from.
 *
 * `audio-playback`, *Where a listening position is written*: a pause, a jump the listener
 * chose, the app leaving the foreground, the end of a session, and a floor of fifteen seconds
 * under all of them.
 *
 * **Two defects, measured on 2026-09-08.** Nothing wrote on a pause, so a listener who paused
 * and then lost the process lost whatever the tick had not reached. And the tick built its
 * position out of `PlaybackHost.nowPlaying` — a snapshot [PlaybackCentre.publish] takes when
 * the player raises a callback. media3 raises one for a seek, a transition and a pause; it
 * raises none for the clock running on. So a book playing through one long file wrote the
 * offset it started at, for as long as it played, and a pause-triggered write of that same
 * snapshot would have looked like a fix.
 *
 * That is why every assertion below moves the player **without** letting it report: `reach`
 * and `reachPart` on [FakePlayer] raise no callback, exactly as a running clock does not.
 *
 * Robolectric because a `MediaItem` reaches `Uri.parse`. Nothing here needs a decoder.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class RecordedPositionTest {

    /** A folder of two files, so a part index means something. */
    private fun book() = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = listOf(
            Audiobook.AudioPart("file:///sea-room-01.m4a", "One"),
            Audiobook.AudioPart("file:///sea-room-02.m4a", "Two"),
        ),
    )

    /** A book playing, the way `PlaybackHost.start` starts one, and a list of what it wrote. */
    private fun started(
        player: FakePlayer,
        written: MutableList<PlaybackPosition>,
    ): PlaybackCentre {
        val centre = PlaybackCentre(record = { _, at -> written += at })
        val source = AudiobookSource(book(), player)
        source.prepare()
        centre.start(source)
        return centre
    }

    @Test
    fun `a pause writes where the player is, not where the last report said`() {
        val written = mutableListOf<PlaybackPosition>()
        val player = FakePlayer()
        val centre = started(player, written)
        player.reachPart(1, 92_000)
        // The snapshot the surfaces read is still at zero, which is the whole point: `publish`
        // takes one when the player raises a callback, and a clock running on raises none. A
        // write built from it would store the start of the book over an hour of listening.
        assertEquals(0L, centre.nowPlaying?.offsetMillis)

        centre.toggle()

        assertEquals(listOf(PlaybackPosition(1, 92_000)), written)
    }

    /**
     * The commonest pause of all, and the one a write in [PlaybackCentre.toggle] would miss.
     *
     * media3 hands a lock-screen, shade, car or headset pause straight to the player it
     * wraps. The app's centre is never called; it hears the result as a change of state,
     * which is what [PlaybackCentre.publish] reads. Pausing the player directly below is
     * exactly what the system does.
     */
    @Test
    fun `a pause the system delivered to the player is written too`() {
        val written = mutableListOf<PlaybackPosition>()
        val player = FakePlayer()
        val centre = started(player, written)
        player.reach(51_000)

        player.pause()

        assertEquals(listOf(PlaybackPosition(0, 51_000)), written)
        assertEquals(PauseCause.LISTENER, centre.nowPlaying?.session?.pausedBy)
    }

    @Test
    fun `a write asked for at any moment reads the player at that moment`() {
        val written = mutableListOf<PlaybackPosition>()
        val player = FakePlayer()
        val centre = started(player, written)
        // The floor's own call, and the activity's on the way to the background.
        player.reach(37_000)

        centre.recordReached()

        assertEquals(listOf(PlaybackPosition(0, 37_000)), written)
    }

    @Test
    fun `a skip writes the place it landed`() {
        val written = mutableListOf<PlaybackPosition>()
        val player = FakePlayer()
        val centre = started(player, written)
        // A folder's parts have no length until the decoder measures them, and a skip that
        // cannot do the arithmetic does not move. See `AudiobookSkipTest`.
        player.measure(120_000, 90_000)
        player.reach(60_000)

        centre.skip(SkipDirection.FORWARD)

        val landed = 60_000 + SkipIntervals.millis(SkipDirection.FORWARD)
        assertEquals(listOf(PlaybackPosition(0, landed)), written)
    }

    @Test
    fun `a scrub in progress writes nothing`() {
        val written = mutableListOf<PlaybackPosition>()
        val centre = started(FakePlayer(), written)
        // The Compose slider calls `seek` on every pixel of a drag. A store written sixty
        // times a second is a different defect, so the drag's end is what writes — see
        // `PlayerScreen`'s `onValueChangeFinished`.
        repeat(20) { step -> centre.seek(PlaybackPosition(0, step * 500L)) }

        assertEquals(emptyList<PlaybackPosition>(), written)
    }
}
