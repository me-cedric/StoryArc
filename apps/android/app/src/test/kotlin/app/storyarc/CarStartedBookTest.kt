package app.storyarc

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `audio-playback` task 13.3: a car choosing a book through `PlaybackService.onSetMediaItems`
 * never calls `PlayingBook.play`, so nothing pointed `reading-progress`'s writer at it and
 * every position the car's own session reached was dropped. `carStartedBook` is the rule
 * `PlayingBook.watchCarStarts` asks on every `PlaybackHost.nowPlaying` update to notice one
 * and resolve it back to the publication the library already holds.
 */
class CarStartedBookTest {

    private fun book(id: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$id"),
        format = PublicationFormat.M4B,
        displayTitle = id,
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    @Test
    fun `a car's choice is resolved from the library it is already in`() {
        val sea = book("sea-room")
        val found = carStartedBook(followingId = null, playingId = sea.id, publications = listOf(sea))

        assertEquals(sea, found)
    }

    @Test
    fun `nothing is playing, so there is nothing to adopt`() {
        assertNull(carStartedBook(followingId = null, playingId = null, publications = listOf(book("a"))))
    }

    @Test
    fun `the book already followed is not re-adopted`() {
        val sea = book("sea-room")
        assertNull(carStartedBook(followingId = sea.id, playingId = sea.id, publications = listOf(sea)))
    }

    @Test
    fun `an id the library does not hold resolves to nothing, the honest answer for a resumed book`() {
        assertNull(carStartedBook(followingId = null, playingId = "ghost", publications = listOf(book("a"))))
    }

    @Test
    fun `a second book displacing the first is adopted in its place`() {
        val second = book("second")
        val found = carStartedBook(
            followingId = "first",
            playingId = second.id,
            publications = listOf(book("first"), second),
        )

        assertEquals(second, found)
    }
}
