package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A book the car started directly, over a player nothing was attached to.
 *
 * `audio-playback`: a car's own transport controls reach the same session every other
 * surface reads. `PlaybackService.LibraryCallback.onSetMediaItems` used to hand the car's
 * choice straight to the decoder with no [PlayerSource] over it at all — no
 * `reading-progress` write, no [PlaybackMemory] kept current. [AudiobookSource.attach] and
 * [PlaybackCentre.attach] are the half of the fix a host test can reach without a real
 * `MediaSession`: the source watches a player something else is loading and starting,
 * instead of [AudiobookSource.play]'s own [AudiobookSource.prepare] loading it a second time.
 *
 * Robolectric because a `MediaItem` reaches `Uri.parse`. Nothing here needs a decoder.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class CarStartTest {

    private fun book() = Audiobook(
        id = "sea-room",
        title = "Sea Room",
        sources = listOf(Audiobook.AudioPart("file:///sea-room.m4b", "Sea Room")),
    )

    @Test
    fun `attaching does not load the player a second time`() {
        val player = FakePlayer()
        val source = AudiobookSource(book(), player)

        source.attach()

        // `prepare` is what calls `setMediaItems`. A player the car is still resolving items
        // for holds none yet, and attach must not be the second caller of that method.
        assertNull(player.currentMediaItem)
    }

    @Test
    fun `attaching marks the session active without starting the player`() {
        val player = FakePlayer()
        val source = AudiobookSource(book(), player)

        source.attach()

        assertTrue(source.session.isActive)
        assertFalse(player.playWhenReady)
    }

    @Test
    fun `the centre surfaces an attached book without playing it`() {
        val player = FakePlayer()
        val source = AudiobookSource(book(), player)
        source.attach()
        val centre = PlaybackCentre()

        centre.attach(source)

        assertEquals("sea-room", centre.playingId)
        assertFalse(player.playWhenReady)
    }

    @Test
    fun `attaching writes no position for the book just attached`() {
        val recorded = mutableListOf<PlaybackPosition>()
        val player = FakePlayer()
        val source = AudiobookSource(book(), player)
        source.attach()
        val centre = PlaybackCentre(record = { _, at -> recorded += at })

        centre.attach(source)

        assertEquals(emptyList<PlaybackPosition>(), recorded)
    }

    /**
     * The point of the whole fix: once attached, the car's own commands — reaching the
     * player directly, never through this centre — still move the surface every other
     * screen reads.
     *
     * `attach` itself marks the session started, which is true of a book still buffering
     * and would pass with no listener registered at all — see `PlayerStartTest`. A real
     * pause the player reports is what only the listener [prepare] would otherwise have
     * added can catch, so that is what this plays back.
     */
    @Test
    fun `a pause the player reports reaches the surface once attached`() {
        val player = FakePlayer()
        val source = AudiobookSource(book(), player)
        source.attach()
        val centre = PlaybackCentre()
        centre.attach(source)
        // The car's own session commands, not calls through this centre.
        player.play()

        player.pause()

        assertFalse(requireNotNull(centre.nowPlaying).isPlaying)
        assertEquals(PauseCause.LISTENER, centre.nowPlaying?.session?.pausedBy)
    }
}
