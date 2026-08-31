package app.storyarc.feature.library

import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * What a reader may do to a curated order, and what they may not.
 *
 * `library-browsing`'s *Default order in a reading list* and *Overriding a curated order*,
 * which are three promises: the curated order is the default, another field applies for the
 * session, and "the curated order itself is not modified". The third is the one that would rot
 * quietly — a sort that wrote back, or a move taken while a sort was overriding the list,
 * scrambles someone else's reading path and nothing on screen says so until the next time it
 * is opened.
 *
 * iOS's `ListOrderTests` asserts these cases one for one.
 */
class ListOrderTest {

    /** Three publications whose title order is deliberately not their list order. */
    private val library = listOf(
        publication("nightjar", "Nightjar", 1994),
        publication("ashfall", "Ashfall", 2011),
        publication("cinders", "Cinders", 2003),
    )

    /** The curated order: what someone laid out, which is none of the sorts below. */
    private val curatedEntries =
        listOf("path:/fixtures/nightjar.cbz", "path:/fixtures/ashfall.cbz", "path:/fixtures/cinders.cbz")

    private fun publication(slug: String, title: String, year: Int) = Publication(
        identity = PublicationIdentity(normalizedPath = "/fixtures/$slug.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        year = year,
        origin = MetadataOrigin.INFERRED,
    )

    private fun titles(ids: List<String>) =
        ids.map { id -> library.firstOrNull { it.id == id }?.displayTitle ?: id }

    private fun byTitle(ascending: Boolean = true) =
        ListOrder(sort = LibrarySort.TITLE, ascending = ascending)

    @Test
    fun `a list opens in the order it was made in, not alphabetically`() {
        assertTrue(ListOrder.CURATED.isCurated)
        assertNull(ListOrder.CURATED.sort)
        val shown = ListOrdering.arrange(curatedEntries, ListOrder.CURATED, library, Locale.UK)
        assertEquals(listOf("Nightjar", "Ashfall", "Cinders"), titles(shown))
    }

    @Test
    fun `the curated order is handed back rather than re-sorted into itself`() {
        // Identity, not "sorted by whatever the curated order happens to look like". An entry
        // the library cannot answer for proves it: nothing could sort that one, and it still
        // comes back exactly where the list put it.
        val entries = listOf("b", "gone", "a")
        assertEquals(entries, ListOrdering.arrange(entries, ListOrder.CURATED, library, Locale.UK))
    }

    @Test
    fun `a chosen field reorders what is drawn`() {
        val shown = ListOrdering.arrange(curatedEntries, byTitle(), library, Locale.UK)
        assertEquals(listOf("Ashfall", "Cinders", "Nightjar"), titles(shown))
    }

    @Test
    fun `descending is the same order the other way round`() {
        val shown = ListOrdering.arrange(curatedEntries, byTitle(ascending = false), library, Locale.UK)
        assertEquals(listOf("Nightjar", "Cinders", "Ashfall"), titles(shown))
    }

    @Test
    fun `a chosen field uses the library's own comparator rather than a second one`() {
        // The reason this matters is collation: a list sorted by title has to agree with the
        // shelf about where an accented title goes, and two comparators would eventually
        // disagree without either of them looking wrong.
        val order = ListOrder(sort = LibrarySort.YEAR)
        val shown = ListOrdering.arrange(curatedEntries, order, library, Locale.UK)
        val shelf = LibraryIndex.arrange(
            publications = library,
            query = LibraryQuery(sort = LibrarySort.YEAR),
            locale = Locale.UK,
        ).map { it.id }
        assertEquals(shelf, shown)
    }

    @Test
    fun `a chosen field reaches the progress the sort asks about`() {
        // Last read is one of the seven fields, and it is answerable only from outside the
        // publication. A closure that never arrived would sort every entry as never-read and
        // leave the list in its curated order while claiming to have sorted it.
        val read = mapOf(
            "path:/fixtures/cinders.cbz" to 3_000L,
            "path:/fixtures/nightjar.cbz" to 1_000L,
        )
        val shown = ListOrdering.arrange(
            entries = curatedEntries,
            order = ListOrder(sort = LibrarySort.LAST_READ),
            publications = library,
            locale = Locale.UK,
        ) { LibraryIndex.Progress(ReadState.IN_PROGRESS, 0.5, read[it.id]) }
        // Most recent first, and the one never opened last — the shelf's own rule.
        assertEquals(listOf("Cinders", "Nightjar", "Ashfall"), titles(shown))
    }

    @Test
    fun `sorting does not modify the curated order`() {
        val entries = curatedEntries
        ListOrdering.arrange(entries, byTitle(), library, Locale.UK)
        assertEquals(curatedEntries, entries)
        // And returning to it gives back exactly what the list holds.
        assertEquals(
            curatedEntries,
            ListOrdering.arrange(entries, ListOrder.CURATED, library, Locale.UK),
        )
    }

    @Test
    fun `entries may be rearranged in the curated order and nowhere else`() {
        // The up and down buttons move an entry by the position it occupies *as drawn*. Taken
        // while a sort was overriding the list, that position would be written into the curated
        // order — which is precisely what the third clause forbids.
        assertTrue(ListOrder.CURATED.allowsReordering)
        assertFalse(byTitle().allowsReordering)
        assertFalse(ListOrder(LibrarySort.PROGRESS, ascending = false).allowsReordering)
    }

    @Test
    fun `an entry the library cannot answer for keeps the tail, in the list's own order`() {
        // It is not dropped — the list still holds it — and it is not sorted on facts nobody
        // has. Last, and in the list's own order among its own kind, is what is decidable.
        val entries = listOf(
            "gone-b",
            "path:/fixtures/nightjar.cbz",
            "gone-a",
            "path:/fixtures/ashfall.cbz",
        )
        assertEquals(
            listOf("path:/fixtures/ashfall.cbz", "path:/fixtures/nightjar.cbz", "gone-b", "gone-a"),
            ListOrdering.arrange(entries, byTitle(), library, Locale.UK),
        )
    }

    @Test
    fun `nothing is lost or invented by sorting`() {
        val entries = curatedEntries + "gone"
        val shown = ListOrdering.arrange(entries, byTitle(), library, Locale.UK)
        assertEquals(entries.toSet(), shown.toSet())
        assertEquals(entries.size, shown.size)
    }

    @Test
    fun `the number beside a row is its place in the list, never its place on screen`() {
        val numbers = ListOrdering.positions(curatedEntries)
        assertEquals(1, numbers["path:/fixtures/nightjar.cbz"])
        assertEquals(2, numbers["path:/fixtures/ashfall.cbz"])
        assertEquals(3, numbers["path:/fixtures/cinders.cbz"])

        // Sorted by title, Ashfall is drawn first and is still the second entry in the list.
        val shown = ListOrdering.arrange(curatedEntries, byTitle(), library, Locale.UK)
        assertEquals("path:/fixtures/ashfall.cbz", shown.first())
        assertEquals(2, numbers[shown[0]])
    }

    @Test
    fun `an empty list numbers nothing`() {
        assertTrue(ListOrdering.positions(emptyList()).isEmpty())
        assertTrue(ListOrdering.arrange(emptyList(), byTitle(), library, Locale.UK).isEmpty())
    }
}
