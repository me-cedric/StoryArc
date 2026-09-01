package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * What a service the system starts on its own can find out about the book that was playing.
 *
 * `PlaybackService.onPlaybackResumption` is what makes the notification-shade carousel work
 * after process death, and `onGetChildren` is what gives a car something to browse. Both
 * answered from a process-wide field, which is **null in exactly the case they exist for** —
 * a process that has just been created. So the callbacks were written and could not fire
 * usefully, and this is the store that closes it.
 *
 * Robolectric because `SharedPreferences` is a framework component. Nothing here decodes.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlaybackMemoryTest {

    private fun memory() = PlaybackMemory.open(RuntimeEnvironment.getApplication())

    private val folder = Audiobook(
        id = "path:/books/sea-room",
        title = "Sea Room",
        author = "Adam Nicolson",
        sources = listOf(
            Audiobook.AudioPart("file:///books/sea-room/01.mp3", "The Shiants"),
            Audiobook.AudioPart("file:///books/sea-room/02.mp3", "Bird Island"),
        ),
        artworkUri = "file:///books/sea-room/cover.jpg",
    )

    @Before
    fun clean() {
        memory().forget()
    }

    @Test
    fun `a device that has never played a book remembers nothing`() {
        assertNull(memory().last())
    }

    @Test
    fun `a book comes back with its parts, its titles and its place`() {
        val memory = memory()
        memory.remember(folder, partIndex = 1, offsetMillis = 42_000)

        val last = memory.last()
        assertEquals("path:/books/sea-room", last?.id)
        assertEquals("Sea Room", last?.title)
        assertEquals("Adam Nicolson", last?.author)
        assertEquals(
            listOf("file:///books/sea-room/01.mp3", "file:///books/sea-room/02.mp3"),
            last?.uris,
        )
        assertEquals(listOf("The Shiants", "Bird Island"), last?.partTitles)
        assertEquals(1, last?.partIndex)
        assertEquals(42_000L, last?.offsetMillis)
    }

    /** The row a car or a carousel draws states the chapter, not the file. */
    @Test
    fun `the part being played is named`() {
        val memory = memory()
        memory.remember(folder, partIndex = 1, offsetMillis = 0)

        assertEquals("Bird Island", memory.last()?.partTitle)
    }

    @Test
    fun `moving the place leaves the book alone`() {
        val memory = memory()
        memory.remember(folder, partIndex = 0, offsetMillis = 0)

        memory.moveTo(folder.id, partIndex = 1, offsetMillis = 8_000)

        val last = memory.last()
        assertEquals(1, last?.partIndex)
        assertEquals(8_000L, last?.offsetMillis)
        assertEquals(2, last?.uris?.size)
    }

    /**
     * A position for a book that is not the one remembered is not written.
     *
     * The alternative is a carousel row naming one book and playing another, which is the
     * failure this whole store exists to avoid a version of.
     */
    @Test
    fun `a place belonging to another book is ignored`() {
        val memory = memory()
        memory.remember(folder, partIndex = 0, offsetMillis = 0)

        memory.moveTo("path:/books/something-else", partIndex = 4, offsetMillis = 99_000)

        assertEquals(0, memory.last()?.partIndex)
    }

    @Test
    fun `forgetting it leaves nothing to resume`() {
        val memory = memory()
        memory.remember(folder, partIndex = 1, offsetMillis = 42_000)

        memory.forget()

        assertNull(memory.last())
    }

    /**
     * A title list shorter than the URI list does not throw inside a system callback.
     *
     * Written together and read apart, so the two can disagree — and a resumption callback
     * the system is waiting on is the worst place to find out.
     */
    @Test
    fun `a part with no title is a part with an empty title`() {
        val memory = memory()
        memory.remember(
            folder.copy(
                sources = listOf(
                    Audiobook.AudioPart("file:///books/one.m4b", ""),
                    Audiobook.AudioPart("file:///books/two.m4b", ""),
                ),
            ),
            partIndex = 1,
            offsetMillis = 0,
        )

        assertEquals(listOf("", ""), memory.last()?.partTitles)
    }
}
