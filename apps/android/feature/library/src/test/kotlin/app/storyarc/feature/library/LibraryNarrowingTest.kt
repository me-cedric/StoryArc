package app.storyarc.feature.library

import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.ReadState
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the filter chip counts, and what one action puts back.
 *
 * `library-browsing`, *Combining filters*: the filters "combine with AND, the active count is
 * visible on the filter control, and a single action clears them all". *Filter persistence*
 * adds the consequence: "the app never silently returns a filtered view that looks like an
 * empty library -- the empty state says filters are active and offers to clear them".
 *
 * Both sentences are about **agreement** between a number and a button. A badge that counts
 * two groups over a shelf three groups are hiding, or a button that clears two of the three,
 * leaves a reader looking at an empty shelf with nothing on screen that undoes it.
 *
 * The rule used to live in the views: `narrowingCount` was a private function in
 * `LibraryFilterMenu`, and the clearing was written out twice inside `LibraryScreen`'s
 * composable body. Nothing could reach any of the three, so nothing held them to each other.
 * [LibraryNarrowing] is the one value all three now ask, which is what makes this file
 * possible. iOS's `NarrowingRuleTests` asserts the same table against its own twin.
 */
class LibraryNarrowingTest {

    private val library = LibraryScope.OneSource(UUID.randomUUID())

    @Test
    fun `a library nobody has narrowed counts nothing and offers nothing to clear`() {
        val untouched = LibraryNarrowing(LibraryQuery())

        assertEquals(0, untouched.activeCount)
        assertFalse(untouched.isActive)
    }

    @Test
    fun `narrowing to one library is counted, like every other filter`() {
        // The half of the defect a reader could see: the chip drew itself untouched over a
        // shelf it had cut to one library.
        val scoped = LibraryNarrowing(LibraryQuery(scope = library))

        assertEquals(1, scoped.activeCount)
        assertTrue(scoped.isActive)
    }

    @Test
    fun `the download group is counted, because it hides rows nothing else explains`() {
        val narrowing = LibraryNarrowing(LibraryQuery(), downloads = DownloadFilter.DOWNLOADED)

        assertEquals(1, narrowing.activeCount)
    }

    @Test
    fun `the three narrowings add up rather than counting the query's alone`() {
        val query = LibraryQuery(
            readStates = setOf(ReadState.UNREAD),
            genres = setOf("Manga"),
            scope = library,
        )

        // Two facets, one library, one download group.
        assertEquals(
            4,
            LibraryNarrowing(query, downloads = DownloadFilter.DOWNLOADED).activeCount,
        )
    }

    @Test
    fun `clearing puts every group back, so the badge cannot outlive the button`() {
        val narrowing = LibraryNarrowing(
            query = LibraryQuery(
                readStates = setOf(ReadState.FINISHED),
                publishers = setOf("DC"),
                scope = library,
            ),
            downloads = DownloadFilter.DOWNLOADED,
            availability = LibraryAvailability.ON_THIS_DEVICE,
        )

        val cleared = narrowing.cleared()

        assertEquals(0, cleared.activeCount)
        assertEquals(LibraryScope.AllSources, cleared.query.scope)
        assertEquals(DownloadFilter.EITHER, cleared.downloads)
        assertEquals(LibraryAvailability.EVERYTHING, cleared.availability)
    }

    @Test
    fun `the filter menu's own action keeps the term the reader can still see`() {
        val narrowing = LibraryNarrowing(
            LibraryQuery(search = "kestrel", genres = setOf("Manga")),
        )

        assertEquals("kestrel", narrowing.cleared().query.search)
    }

    @Test
    fun `the empty state's action drops the term as well, because the term emptied the shelf`() {
        val narrowing = LibraryNarrowing(
            LibraryQuery(search = "kestrel", genres = setOf("Manga")),
        )

        assertEquals("", narrowing.cleared(includingSearch = true).query.search)
    }

    @Test
    fun `clearing leaves the sort alone, because an order hides nothing`() {
        // A reader who cleared their filters did not ask to be returned to A-Z. The sort is
        // not a narrowing and is not in the count either, so it must not be in the undo.
        val query = LibraryQuery(
            sort = LibrarySort.DATE_ADDED,
            ascending = false,
            tags = setOf("Horror"),
        )

        val cleared = LibraryNarrowing(query).cleared()

        assertEquals(LibrarySort.DATE_ADDED, cleared.query.sort)
        assertFalse(cleared.query.ascending)
    }
}
