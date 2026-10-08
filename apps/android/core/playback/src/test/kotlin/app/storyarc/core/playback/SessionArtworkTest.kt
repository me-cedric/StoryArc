package app.storyarc.core.playback

import android.net.Uri
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Where the picture the system's own controls show comes from, once it no longer waits for the
 * full player. `audiobooks-and-playback` task 4.4b.
 *
 * The app draws the picture the moment a session starts, which is earlier than the controller
 * has connected, so the host has to keep it for the source it is for. A picture that was
 * dropped here is a shade with no artwork for a coverless book that was started and left.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class SessionArtworkTest {

    private val picture = Uri.parse("file:///cache/player-artwork/sea.png")

    private fun source(id: String, player: FakePlayer): AudiobookSource = AudiobookSource(
        Audiobook(id = id, title = id, sources = listOf(Audiobook.AudioPart("file:///$id.m4b", "One"))),
        player,
    )

    @After
    fun quiet() = PlaybackHost.stop()

    @Test
    fun `a picture drawn before the source exists reaches it when it is held`() {
        PlaybackHost.setArtwork("sea-room", picture)
        val player = FakePlayer()
        val sea = source("sea-room", player)

        PlaybackHost.hold(sea)
        sea.prepare()

        assertEquals(picture, player.currentMediaItem?.mediaMetadata?.artworkUri)
    }

    @Test
    fun `a picture drawn for another book is not put on this one`() {
        PlaybackHost.setArtwork("long-field", picture)
        val player = FakePlayer()
        val sea = source("sea-room", player)

        PlaybackHost.hold(sea)
        sea.prepare()

        assertNull(player.currentMediaItem?.mediaMetadata?.artworkUri)
    }

    @Test
    fun `a picture drawn after the book is held replaces the items' artwork in place`() {
        val player = FakePlayer()
        val sea = source("sea-room", player)
        PlaybackHost.hold(sea)
        sea.prepare()
        assertNull(player.currentMediaItem?.mediaMetadata?.artworkUri)

        PlaybackHost.setArtwork("sea-room", picture)

        assertEquals(picture, player.currentMediaItem?.mediaMetadata?.artworkUri)
    }

    @Test
    fun `a picture is given to the source once, and not to the next one held`() {
        PlaybackHost.setArtwork("sea-room", picture)
        PlaybackHost.hold(source("sea-room", FakePlayer()))

        val next = FakePlayer()
        val again = source("sea-room", next)
        PlaybackHost.hold(again)
        again.prepare()

        assertNull(next.currentMediaItem?.mediaMetadata?.artworkUri)
    }

    private fun played(id: String) = PlayedBook(
        id = id,
        title = id,
        author = null,
        artworkUri = null,
        uris = listOf("file:///$id.m4b"),
        partTitles = listOf("One"),
        partIndex = 0,
        offsetMillis = 0,
    )

    private fun remembered(): PlayedBook? =
        PlaybackMemory.open(RuntimeEnvironment.getApplication()).last()

    /** Task 4.4b: a resume after process death reads the drawn picture from this record. */
    @Test
    fun `a picture drawn for the held book is remembered for a resume`() {
        PlaybackHost.attachCarStart(RuntimeEnvironment.getApplication(), played("sea-room"), FakePlayer())

        PlaybackHost.setArtwork("sea-room", picture)

        assertEquals(picture.toString(), remembered()?.artworkUri)
    }

    @Test
    fun `a picture drawn before the book is held is remembered when it is held`() {
        PlaybackHost.setArtwork("sea-room", picture)

        PlaybackHost.attachCarStart(RuntimeEnvironment.getApplication(), played("sea-room"), FakePlayer())

        assertEquals(picture.toString(), remembered()?.artworkUri)
    }
}
