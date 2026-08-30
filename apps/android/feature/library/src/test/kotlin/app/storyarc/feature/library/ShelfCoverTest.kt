package app.storyarc.feature.library

import app.storyarc.core.model.CompositeCover
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which covers a reading list stands behind.
 *
 * `collections-and-reading-lists` writes the rule for a collection -- "a composite of its
 * first four member covers" -- and [CompositeCover] implements it. A reading list needs the
 * same picture and cannot use the same rule: a collection is a set, ordered by identity so
 * that sorting the library does not rearrange the artwork, and a list's order is the thing
 * it exists to hold.
 *
 * iOS's `ShelfCoverTests` asserts these cases one for one. Two apps that composed a shelf
 * differently would be one product wearing two faces, which is the divergence this suite
 * exists to catch.
 */
class ShelfCoverTest {

    private fun list(entries: List<String>) = ReadingList(name = "Crossover", entries = entries)

    @Test
    fun `a list of four or more shows its first four in its own order`() {
        val entries = listOf("zulu", "alpha", "mike", "bravo", "kilo")
        assertEquals(listOf("zulu", "alpha", "mike", "bravo"), shelfTiles(list(entries)))
    }

    @Test
    fun `exactly four is the quadrant not the single cover`() {
        assertEquals(
            CompositeCover.TILE_COUNT,
            shelfTiles(list(listOf("a", "b", "c", "d"))).size,
        )
    }

    @Test
    fun `fewer than four shows one cover across the frame`() {
        assertEquals(listOf("a"), shelfTiles(list(listOf("a", "b", "c"))))
        assertEquals(listOf("only"), shelfTiles(list(listOf("only"))))
    }

    @Test
    fun `an empty list has nothing to draw`() {
        assertTrue(shelfTiles(list(emptyList())).isEmpty())
    }

    @Test
    fun `reordering a list redraws it because the order is what it means`() {
        val before = list(listOf("a", "b", "c", "d", "e"))
        val after = before.copy(entries = listOf("e", "a", "b", "c", "d"))
        assertNotEquals(shelfTiles(before), shelfTiles(after))
    }

    @Test
    fun `a collection is ordered by identity so sorting the library leaves it alone`() {
        val one = PublicationCollection(name = "Set", members = setOf("d", "a", "c", "b"))
        val two = PublicationCollection(name = "Set", members = setOf("b", "c", "a", "d"))
        assertEquals(shelfTiles(one), shelfTiles(two))
        assertEquals(listOf("a", "b", "c", "d"), shelfTiles(one))
    }
}

/** How far through an ordered shelf the card's rail says the reader is. */
class ShelfFractionTest {

    @Test
    fun `nothing read is no rail at all`() {
        val list = ReadingList(name = "List", entries = listOf("a", "b", "c"))
        assertEquals(0f, shelfFraction(list, emptySet()), 0f)
    }

    @Test
    fun `a finished list fills the rail exactly once`() {
        val list = ReadingList(name = "List", entries = listOf("a", "b"))
        assertEquals(1f, shelfFraction(list, setOf("a", "b")), 0f)
    }

    @Test
    fun `an empty list is not a division by nought`() {
        assertEquals(0f, shelfFraction(ReadingList(name = "List"), emptySet()), 0f)
    }

    /**
     * The card counts what [ReadingList.position] counts -- everything before the first
     * unfinished entry -- so a reader who skipped ahead is not told they are further along
     * than they are.
     */
    @Test
    fun `skipping ahead does not move the rail`() {
        val list = ReadingList(name = "List", entries = listOf("a", "b", "c", "d"))
        assertEquals(0f, shelfFraction(list, setOf("d")), 0f)
    }
}
