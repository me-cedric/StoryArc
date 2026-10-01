package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which badge a local reading list's row stands behind.
 *
 * `collections-and-reading-lists`' delta: "each entry states its own read state -- finished,
 * part-read with the position reached, or unread -- in the same terms the library uses for a
 * publication". [readingListRowBadge] is the rule, free of Compose so it can be asserted
 * without a window -- the same split [ServerListProgressTest] makes for its own sibling
 * decision. iOS's `ReadingListRowStateTests` makes the same three-way claim.
 */
class ReadingListRowStateTest {

    @Test
    fun `finished wins whatever percent is handed in alongside it`() {
        assertEquals(
            ReadingListRowBadge.Finished,
            readingListRowBadge(isFinished = true, percentRead = 10),
        )
        assertEquals(
            ReadingListRowBadge.Finished,
            readingListRowBadge(isFinished = true, percentRead = null),
        )
    }

    @Test
    fun `a known percent short of finished is part-read`() {
        assertEquals(
            ReadingListRowBadge.PartRead(40),
            readingListRowBadge(isFinished = false, percentRead = 40),
        )
    }

    @Test
    fun `neither finished nor a known percent is nothing to say`() {
        assertEquals(
            ReadingListRowBadge.None,
            readingListRowBadge(isFinished = false, percentRead = null),
        )
    }
}
