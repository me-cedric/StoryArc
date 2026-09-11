package app.storyarc.feature.library

import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * Which letters the index offers, and the five sorts under which it offers none.
 *
 * `library-browsing`'s *An index down the side of a long shelf* and *A sort no letter
 * describes* scenarios are what these cases hold. iOS's `LibraryRailTests` answers the same
 * ones.
 */
class LibraryRailTest {

    private val english = Locale.ENGLISH

    private fun issue(title: String, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.EMBEDDED,
    )

    /** One more than [LibrarySections.THRESHOLD], which is what makes a shelf long. */
    private val letters = listOf(
        "Ashfall", "Blackwater", "Cinder", "Drift", "Ember", "Fathom", "Glass",
        "Harrow", "Ironwood", "Jubilee", "Kestrel", "Lantern", "Moth",
    )

    @Test
    fun `a title sort offers one entry per letter the shelf files a row under`() {
        val shelf = letters.map { issue(it) }
        val entries = LibraryRail.of(shelf, LibrarySort.TITLE, english)

        assertEquals(
            listOf("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"),
            entries.map { it.label },
        )
        assertEquals(shelf.first().id, entries.first().publicationId)
    }

    /**
     * The sort key, not the raw title. `library-browsing` alphabetises a title with its
     * leading article ignored, so a label read off the raw title would say T in the middle of
     * the S run and the index would stop describing the shelf.
     */
    @Test
    fun `The Sandman files under S`() {
        val shelf = (listOf("The Sandman") + letters.drop(1)).map { issue(it) }
        val entries = LibraryRail.of(shelf, LibrarySort.TITLE, english)

        assertEquals("S", entries.first().label)
        assertTrue(entries.none { it.label == "T" })
    }

    @Test
    fun `a title no letter claims is offered as hash`() {
        val shelf = (listOf("2000 AD") + letters.drop(1)).map { issue(it) }

        assertEquals("#", LibraryRail.of(shelf, LibrarySort.TITLE, english).first().label)
    }

    @Test
    fun `five sorts file nothing under a letter, and offer no index at all`() {
        val shelf = letters.map { issue(it) }
        val silent = listOf(
            LibrarySort.LAST_READ,
            LibrarySort.PROGRESS,
            LibrarySort.YEAR,
            LibrarySort.DATE_ADDED,
            LibrarySort.FILE_SIZE,
        )

        for (sort in silent) {
            assertEquals(sort.name, emptyList<RailEntry>(), LibraryRail.of(shelf, sort, english))
        }
    }

    /**
     * The whole of the hide-rather-than-disable decision: the caller draws nothing, so no
     * reader meets a control that refuses every touch.
     */
    @Test
    fun `a shelf short enough to scan offers no index`() {
        val shelf = letters.take(LibrarySections.THRESHOLD).map { issue(it) }

        assertEquals(LibrarySections.THRESHOLD, shelf.size)
        assertEquals(emptyList<RailEntry>(), LibraryRail.of(shelf, LibrarySort.TITLE, english))
    }

    @Test
    fun `one letter over the whole shelf is a label rather than an index`() {
        val shelf = (1..13).map { issue("Ashfall #$it") }

        assertEquals(emptyList<RailEntry>(), LibraryRail.of(shelf, LibrarySort.TITLE, english))
    }

    /**
     * `LibraryIndex` puts every series-less publication after every series, in one pile, so
     * the `#` entry is one contiguous run at the end rather than a second alphabet run
     * through the first.
     */
    @Test
    fun `a series sort files a publication naming no series under hash`() {
        val shelf = (1..10).map { issue("issue $it", "Lantern") } + (1..3).map { issue("loose $it") }
        val entries = LibraryRail.of(shelf, LibrarySort.SERIES, english)

        assertEquals(listOf("L", "#"), entries.map { it.label })
        assertEquals(shelf[10].id, entries[1].publicationId)
    }

    @Test
    fun `a repeated letter is one entry, pointing at the first row under it`() {
        val shelf = listOf(issue("Ashfall"), issue("Blackwater")) + (1..11).map { issue("Ashfall #$it") }
        val entries = LibraryRail.of(shelf, LibrarySort.TITLE, english)

        assertEquals(listOf("A", "B"), entries.map { it.label })
        assertEquals(shelf.first().id, entries.first().publicationId)
    }

    /**
     * Uppercased for the reader's locale rather than for the machine's, the rule
     * [LibrarySections] already applies to a heading — so a heading and an index entry cannot
     * disagree about one row.
     */
    @Test
    fun `a Turkish shelf files isi under I`() {
        val shelf = listOf(issue("ısı")) + (1..12).map { issue("Zephyr $it") }
        val entries = LibraryRail.of(shelf, LibrarySort.TITLE, Locale.forLanguageTag("tr"))

        assertEquals(listOf("I", "Z"), entries.map { it.label })
    }

    /**
     * A letter's target in the grid is an **item** index, and the grid puts a full-span row
     * before the cells and a sticky header before each section.
     */
    @Test
    fun `an item index counts the leading row and every heading`() {
        val first = (1..3).map { issue("a$it") }
        val second = (1..2).map { issue("b$it") }
        val sections = listOf(
            LibrarySection(id = "0.A", title = "A", publications = first),
            LibrarySection(id = "1.B", title = "B", publications = second),
        )

        val indexes = LibraryRail.itemIndexes(first + second, sections, leading = 1)

        // 0 is the continue-reading row, 1 is the first heading, 2..4 are its covers,
        // 5 is the second heading, 6..7 are its covers.
        assertEquals(2, indexes[first[0].id])
        assertEquals(4, indexes[first[2].id])
        assertEquals(6, indexes[second[0].id])
    }

    @Test
    fun `with no sections and no leading row, a position is the position`() {
        val shelf = (1..4).map { issue("a$it") }

        val indexes = LibraryRail.itemIndexes(shelf, emptyList(), leading = 0)

        assertEquals(0, indexes[shelf[0].id])
        assertEquals(3, indexes[shelf[3].id])
    }
}
