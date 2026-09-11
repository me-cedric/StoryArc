package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two answers the shelf can give about a series, and what is written down for each.
 *
 * `library-browsing`'s *The choice between series and issues* scenario asks for the choice to
 * persist across visits and for series to be the answer a reader who never chose gets. iOS's
 * `LibraryGroupingTests` answers the same cases.
 */
class LibraryGroupingTest {

    @Test
    fun `series collapses and issues does not`() {
        assertTrue(LibraryGrouping.SERIES.isCollapsing)
        assertFalse(LibraryGrouping.ISSUES.isCollapsing)
    }

    @Test
    fun `series is offered first, so it is the answer a menu opens on`() {
        assertEquals(LibraryGrouping.SERIES, LibraryGrouping.entries.first())
        assertEquals(2, LibraryGrouping.entries.size)
    }

    @Test
    fun `every case round-trips through its stored name`() {
        for (grouping in LibraryGrouping.entries) {
            assertEquals(grouping, LibraryGrouping.named(grouping.name))
        }
    }

    @Test
    fun `a name nobody wrote leaves the reader what they already see`() {
        assertEquals(LibraryGrouping.SERIES, LibraryGrouping.named(null))
        assertEquals(LibraryGrouping.SERIES, LibraryGrouping.named("COLLAPSED"))
        assertEquals(LibraryGrouping.SERIES, LibraryGrouping.named(""))
    }
}
