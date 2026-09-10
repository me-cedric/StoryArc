package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a server's two numbers mean about one entry, and about the list they are in.
 *
 * `collections-and-reading-lists` asks a reading list to show "how many entries are finished
 * and where the user's position is", and asks each entry to state its own read state. It also
 * asks for nothing to be claimed where a source reports nothing, which is the case this file
 * exists to keep separate: Kavita sends `pagesRead: 0` for an unread entry *and* for an entry
 * it knows nothing about, and only `pagesTotal` tells them apart.
 *
 * The same claims iOS's `ServerListProgressTests` makes.
 */
class ServerListProgressTest {

    @Test
    fun `nothing read of a known length is unread`() {
        assertEquals(ServerListProgress.State.Unread, ServerListProgress.of(0, 22))
    }

    @Test
    fun `part of a known length carries the position reached`() {
        assertEquals(ServerListProgress.State.Part(50), ServerListProgress.of(11, 22))
    }

    @Test
    fun `every page of a known length is finished`() {
        assertEquals(ServerListProgress.State.Finished, ServerListProgress.of(22, 22))
    }

    @Test
    fun `more pages read than the entry has is still finished`() {
        // Kavita counts a re-read past the end on occasion. It is not 105% read.
        assertEquals(ServerListProgress.State.Finished, ServerListProgress.of(23, 22))
    }

    @Test
    fun `no length is the server saying nothing, which is not unread`() {
        assertEquals(ServerListProgress.State.Unknown, ServerListProgress.of(0, 0))
    }

    @Test
    fun `a part-read entry never rounds to nothing or to everything`() {
        // One page of a long chapter is progress a reader made, and 0% would deny it; a page
        // short of the end is not finished, and 100% would claim it.
        assertEquals(ServerListProgress.State.Part(1), ServerListProgress.of(1, 400))
        assertEquals(ServerListProgress.State.Part(99), ServerListProgress.of(399, 400))
    }

    @Test
    fun `the list counts the entries it knows about`() {
        val counted = ServerListProgress.summary(
            listOf(0 to 22, 11 to 22, 22 to 22, 22 to 22),
        )

        assertEquals(ServerListProgress.Counted(finished = 2, of = 4), counted)
    }

    @Test
    fun `an entry the server says nothing about is in neither number`() {
        val counted = ServerListProgress.summary(listOf(22 to 22, 0 to 0, 0 to 22))

        assertEquals(ServerListProgress.Counted(finished = 1, of = 2), counted)
    }

    @Test
    fun `a list the server says nothing about at all counts nothing`() {
        assertNull(ServerListProgress.summary(listOf(0 to 0, 0 to 0)))
    }
}
