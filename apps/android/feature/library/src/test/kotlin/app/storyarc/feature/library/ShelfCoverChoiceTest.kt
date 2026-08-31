package app.storyarc.feature.library

import app.storyarc.core.model.CompositeCover
import app.storyarc.core.model.PublicationCollection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the cover picker offers a collection, and which of them the collection is wearing.
 *
 * `collections-and-reading-lists`: a collection's cover "is a composite of its first four member
 * covers unless the user sets a specific one". [CompositeCover] has always honoured the second
 * clause; until this picker existed nothing in either app could reach it, so the clause was
 * unreachable rather than merely untested.
 *
 * The picker and the shelf card must never disagree about what is showing, which is why
 * [ShelfCoverChoice.chosen] answers from the same premise [CompositeCover] does rather than from
 * a flag of its own. iOS's `ShelfCoverChoiceTests` asserts these identically.
 */
class ShelfCoverChoiceTest {

    private fun collection(members: Set<String>, cover: String? = null) =
        PublicationCollection(name = "Image Comics", members = members, coverMemberId = cover)

    @Test
    fun `the composite is always offered and offered first`() {
        assertEquals(
            ShelfCoverOption.Composite,
            ShelfCoverChoice.options(collection(setOf("b", "a"))).first(),
        )
        assertEquals(
            ShelfCoverOption.Composite,
            ShelfCoverChoice.options(collection(setOf("a"), cover = "a")).first(),
        )
    }

    /**
     * The same order [CompositeCover] reads members in, so the four on the composite tile are
     * visibly the first four of the row beneath it.
     */
    @Test
    fun `members are offered in identity order the order the composite reads them in`() {
        assertEquals(
            listOf(
                ShelfCoverOption.Composite,
                ShelfCoverOption.Member("alpha"),
                ShelfCoverOption.Member("charlie"),
                ShelfCoverOption.Member("delta"),
            ),
            ShelfCoverChoice.options(collection(setOf("delta", "alpha", "charlie"))),
        )
    }

    @Test
    fun `a collection holding nothing has only the composite to offer`() {
        assertEquals(
            listOf(ShelfCoverOption.Composite),
            ShelfCoverChoice.options(collection(emptySet())),
        )
    }

    @Test
    fun `with no choice made the composite is what is showing`() {
        assertEquals(
            ShelfCoverOption.Composite,
            ShelfCoverChoice.chosen(collection(setOf("a", "b"))),
        )
    }

    @Test
    fun `a chosen member is what is showing and is one of the options`() {
        val picked = collection(setOf("a", "b"), cover = "b")
        assertEquals(ShelfCoverOption.Member("b"), ShelfCoverChoice.chosen(picked))
        assertTrue(ShelfCoverOption.Member("b") in ShelfCoverChoice.options(picked))
    }

    /**
     * [CompositeCover]'s own second guard: a cover that has left the collection is not the
     * collection's cover any more. Answered the same way here, so the tick in the picker cannot
     * land on a book the collection does not contain.
     */
    @Test
    fun `a cover that is no longer a member falls back to the composite`() {
        assertEquals(
            ShelfCoverOption.Composite,
            ShelfCoverChoice.chosen(collection(setOf("a"), cover = "gone")),
        )
    }

    /**
     * The invariant that keeps the picker honest: whatever it says is showing is something it
     * also offers, so there is always a way back to it.
     */
    @Test
    fun `whatever is showing is one of the options`() {
        val cases = listOf(
            collection(emptySet()),
            collection(setOf("a", "b", "c", "d", "e")),
            collection(setOf("a", "b"), cover = "a"),
            collection(setOf("a"), cover = "gone"),
        )
        for (each in cases) {
            assertTrue(ShelfCoverChoice.chosen(each) in ShelfCoverChoice.options(each))
        }
    }
}
