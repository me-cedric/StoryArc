package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CarLibraryTest {

    private fun library() = CarLibrary.open(RuntimeEnvironment.getApplication())

    private val seaRoom = CarBook(
        id = "path:/books/sea-room",
        title = "Sea Room",
        durationMillis = 9_000_000,
        artworkUri = "file:///books/sea-room/cover.jpg",
        uris = listOf("file:///books/sea-room/01.mp3", "file:///books/sea-room/02.mp3"),
    )

    private val theSeaWolf = CarBook(
        id = "path:/books/the-sea-wolf",
        title = "The Sea Wolf",
        uris = listOf("file:///books/the-sea-wolf.m4b"),
    )

    @Before
    fun clean() {
        library().publish(emptyList())
    }

    @Test
    fun `a device that has published nothing offers a car nothing`() {
        assertTrue(library().books().isEmpty())
    }

    @Test
    fun `a book comes back with its title, its length, its cover and its audio`() {
        val library = library()
        library.publish(listOf(seaRoom))

        assertEquals(listOf(seaRoom), library.books())
    }

    @Test
    fun `books come back in the order they were published`() {
        val library = library()
        library.publish(listOf(seaRoom, theSeaWolf))

        assertEquals(
            listOf("path:/books/sea-room", "path:/books/the-sea-wolf"),
            library.books().map { it.id },
        )
    }

    @Test
    fun `publishing again replaces the shelf rather than adding to it`() {
        val library = library()
        library.publish(listOf(seaRoom, theSeaWolf))

        library.publish(listOf(theSeaWolf))

        assertEquals(listOf(theSeaWolf), library.books())
    }

    @Test
    fun `a book with no length is a book with no length, not a book of zero length`() {
        val library = library()
        library.publish(listOf(theSeaWolf))

        assertNull(library.books().single().durationMillis)
    }

    @Test
    fun `a row with no audio is dropped, because a car must not list what it cannot play`() {
        val library = library()
        library.publish(listOf(seaRoom.copy(uris = emptyList()), theSeaWolf))

        assertEquals(listOf(theSeaWolf), library.books())
    }

    @Test
    fun `the book in progress is offered once, not twice`() {
        assertEquals(
            listOf(seaRoom.id, theSeaWolf.id),
            CarShelf.children(seaRoom.asPlayed(), listOf(seaRoom, theSeaWolf)).map { it.id },
        )
    }

    /**
     * The order is the requirement, not a detail of it.
     *
     * `audio-playback` puts the book in progress at the top because a car screen is read at a
     * glance. The shelf below deliberately lists it last, so an implementation that appends
     * the remembered book instead of leading with it fails here.
     */
    @Test
    fun `the book in progress is the first row a car draws`() {
        val children = CarShelf.children(seaRoom.asPlayed(), listOf(theSeaWolf, seaRoom))

        assertEquals(seaRoom.id, children.first().id)
    }

    /**
     * Task 13.2, and the read-aloud clause of 12.1: the live voice is the first row, above
     * the book in progress, and a book is never listed twice.
     */
    @Test
    fun `the live voice is the first row, and each book appears once`() {
        val voice = theSeaWolf.asPlayed().copy(uris = emptyList())

        val children = CarShelf.children(seaRoom.asPlayed(), listOf(theSeaWolf, seaRoom), live = voice)

        assertEquals(listOf(theSeaWolf.id, seaRoom.id), children.map { it.id })
        assertTrue("the shelf's copy replaced the voice's row", children.first().uris.isEmpty())
    }

    @Test
    fun `a car that asks for the second page does not receive the first again`() {
        val rows = CarShelf.children(null, listOf(seaRoom, theSeaWolf))

        assertEquals(
            listOf(theSeaWolf.id),
            CarShelf.page(rows, page = 1, pageSize = 1).map { it.id },
        )
    }

    @Test
    fun `a page past the end of the shelf is empty, not the shelf again`() {
        val rows = CarShelf.children(null, listOf(seaRoom, theSeaWolf))

        assertTrue(CarShelf.page(rows, page = 4, pageSize = 10).isEmpty())
    }

    @Test
    fun `a page with room for everything holds everything`() {
        val rows = CarShelf.children(null, listOf(seaRoom, theSeaWolf))

        assertEquals(rows, CarShelf.page(rows, page = 0, pageSize = Int.MAX_VALUE))
    }

    @Test
    fun `a shelf row starts at the beginning, because nothing has played it`() {
        val played = theSeaWolf.asPlayed()

        assertEquals("path:/books/the-sea-wolf", played.id)
        assertEquals(listOf("file:///books/the-sea-wolf.m4b"), played.uris)
        assertEquals(0, played.partIndex)
        assertEquals(0L, played.offsetMillis)
    }

    /**
     * The defect, from the car's side: `asPlayed` used to answer every row at zero, so a car
     * always offered a finished book's first chapter again.
     */
    @Test
    fun `a shelf row resumes where the listener stopped`() {
        val played = theSeaWolf.copy(partIndex = 2, offsetMillis = 45_000).asPlayed()

        assertEquals(2, played.partIndex)
        assertEquals(45_000L, played.offsetMillis)
    }

    @Test
    fun `a row's position survives a publish and a read back`() {
        val inProgress = theSeaWolf.copy(partIndex = 2, offsetMillis = 45_000)
        val library = library()
        library.publish(listOf(inProgress))

        assertEquals(inProgress, library.books().single())
    }

    /**
     * One builder draws both kinds of row, so a shelf row must carry its length across.
     * Dropping it here is how the two builders drifted apart in the first place.
     */
    @Test
    fun `a shelf row keeps the length it was published with`() {
        assertEquals(9_000_000L, seaRoom.asPlayed().durationMillis)
        assertNull(theSeaWolf.asPlayed().durationMillis)
    }
}
