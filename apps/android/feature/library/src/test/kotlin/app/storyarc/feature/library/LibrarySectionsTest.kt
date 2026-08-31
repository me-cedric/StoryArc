package app.storyarc.feature.library

import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryQuery
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
 * How a long shelf divides, and — as much — when it refuses to.
 *
 * `library-browsing`: a library "more than a reader can scan" is "divided by series where a
 * publication declares one, and otherwise by the active sort key", and "the sections follow
 * the sort rather than replacing it". That last clause is the one worth a suite: a grouping
 * that gathered every "A" from across a shelf would silently undo the order the reader
 * chose, and a screenshot of a phone showing four rows would never reveal it.
 *
 * The refusals matter as much as the divisions. A shelf of unrelated files with a distinct
 * initial each divides into a tall column of near-empty rows, every one of them announced —
 * worse to read than the wall of covers the requirement was written to fix. That was found
 * on a booted simulator, not in this file, and it is asserted here so it cannot come back.
 *
 * **iOS's `LibrarySectionTests`, case for case.** The rule exists twice, so the assertions
 * do too, and the two files are read side by side when either moves.
 */
class LibrarySectionsTest {

    /** The word the screen supplies for everything the library cannot place. */
    private val other = "Other"

    private val english = Locale.forLanguageTag("en-US")

    private fun publication(
        title: String,
        series: String? = null,
        year: Int? = null,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        year = year,
        origin = MetadataOrigin.INFERRED,
    )

    /** A run of one series, long enough that no heading in these shelves is a stray. */
    private fun series(name: String, count: Int) =
        (1..count).map { publication("$name #$it", series = name) }

    private fun divide(shelf: List<Publication>, sort: LibrarySort) =
        LibrarySections.divide(shelf, sort, other, english)

    private fun titles(sections: List<LibrarySection>) =
        sections.map { section -> section.publications.map { it.displayTitle } }

    @Test
    fun `a series the shelf holds more than one of becomes a heading`() {
        val shelf = series("Ashfall", 4) + series("Blackwater", 4)

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals(listOf("Ashfall", "Blackwater"), sections.map { it.title })
        assertEquals(listOf(4, 4), titles(sections).map { it.size })
    }

    @Test
    fun `a series with one publication in it does not earn a heading of its own`() {
        // Three hundred one-shots that each name a series would otherwise become three
        // hundred headings over one cover each, which is less structure than the wall of
        // covers it replaced, not more.
        val shelf = listOf(
            publication("Akira", series = "Akira"),
            publication("Appleseed", series = "Appleseed"),
            publication("Astro Boy", series = "Astro Boy"),
            publication("Berserk", series = "Berserk"),
            publication("Blame", series = "Blame"),
            publication("Blacksad", series = "Blacksad"),
        )

        val sections = divide(shelf, LibrarySort.TITLE)

        assertEquals(listOf("A", "B"), sections.map { it.title })
        assertEquals(listOf(3, 3), titles(sections).map { it.size })
    }

    @Test
    fun `a shelf whose standalones fall either side of a series is not divided`() {
        // This shelf draws *Other*, then *Ashfall*, then *Other* again, and a reader reads
        // the second one as a different pile. Seen on a booted simulator: one stray file
        // sorting before the first series was enough to produce it.
        //
        // `LibraryIndex.compare(by = SERIES)` no longer *hands* the shelf over in this order
        // — a publication with no series now sorts after every publication that has one, and
        // `a mixed library arranged by series divides once standalones sort last` below is
        // the same books arranged by that rule. The order is written out by hand here because
        // the refusal is the backstop: `divide` is given a list, and a list that would repeat
        // a heading has to be refused whatever produced it.
        val shelf = listOf(publication("archive-comment")) +
            series("Ashfall", 6) +
            listOf(publication("truncated"), publication("zip64"), publication("tar-store"))

        assertTrue(divide(shelf, LibrarySort.SERIES).isEmpty())
    }

    @Test
    fun `a mixed library arranged by series divides once standalones sort last`() {
        // The point of sorting a publication with no series after every publication that has
        // one. These are the exact books the refusal above is written over; arranged rather
        // than hand-ordered, the standalones form one contiguous pile at the end and the
        // shelf divides cleanly instead of declining to divide at all.
        val shelf = LibraryIndex.arrange(
            listOf(publication("archive-comment")) +
                series("Ashfall", 6) +
                listOf(publication("truncated"), publication("zip64"), publication("tar-store")),
            LibraryQuery(sort = LibrarySort.SERIES),
            english,
        )

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals(2, sections.size)
        assertEquals("Ashfall", sections[0].title)
        assertEquals(6, sections[0].publications.size)
        // The standalone pile, whole and in one place. Its heading is a word the screen
        // supplies rather than data off a file, so what is asserted is that it holds all four
        // and that no heading is drawn twice.
        assertEquals(
            listOf("archive-comment", "tar-store", "truncated", "zip64"),
            titles(sections)[1],
        )
        assertEquals(sections.size, sections.map { it.title }.toSet().size)
    }

    @Test
    fun `sections are contiguous runs, so the sort survives them`() {
        // The shelf arrives in the order `LibraryIndex.arrange` left it in, and dividing it
        // never moves a publication.
        val shelf = series("Ashfall", 4) + series("Blackwater", 4) + series("Cinderfall", 4)

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals(
            shelf.map { it.displayTitle },
            sections.flatMap { section -> section.publications.map { it.displayTitle } },
        )
    }

    @Test
    fun `every section has its own identity, so two sharing a heading are two places`() {
        val shelf = series("Ashfall", 4) + series("Blackwater", 4)

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals(sections.size, sections.map { it.id }.toSet().size)
    }

    @Test
    fun `a title that starts with no letter files under a symbol rather than under itself`() {
        val shelf = listOf(
            publication("13 Ghosts"),
            publication("300"),
            publication("2000 AD"),
            publication("Akira"),
            publication("Astro Boy"),
            publication("Appleseed"),
        )

        val sections = divide(shelf, LibrarySort.TITLE)

        assertEquals(listOf("#", "A"), sections.map { it.title })
        assertEquals(listOf(3, 3), titles(sections).map { it.size })
    }

    @Test
    fun `a year sort divides by year, and an unknown year is not filed as an early one`() {
        val shelf = listOf(
            publication("Watchmen", year = 1986),
            publication("Maus", year = 1986),
            publication("Dark Knight", year = 1986),
            publication("Unknown A"),
            publication("Unknown B"),
            publication("Unknown C"),
        )

        val sections = divide(shelf, LibrarySort.YEAR)

        assertEquals("1986", sections.first().title)
        assertEquals(2, sections.size)
        assertEquals(listOf(3, 3), titles(sections).map { it.size })
    }

    @Test
    fun `under a series sort, everything with no series shares one heading`() {
        // Filing them under their initials would answer a question the reader did not ask,
        // and would scatter the standalone half of a library across twenty headings that all
        // mean "no series".
        val shelf = series("Ashfall", 4) + listOf(
            publication("Akira"),
            publication("Berserk"),
            publication("Chew"),
            publication("Daytripper"),
        )

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals(2, sections.size)
        assertEquals("Ashfall", sections[0].title)
        assertEquals(4, sections[1].publications.size)
    }

    @Test
    fun `a sort with no natural divisions leaves an unserialised shelf as one run`() {
        // Where the boundary between "recently" and "a while ago" falls is a decision no file
        // carries, and a heading that invented one would be the app asserting something it
        // does not know. A series still earns its heading under these sorts — the requirement
        // puts series first — so this shelf deliberately declares none.
        val shelf = listOf(
            publication("Akira"),
            publication("Berserk"),
            publication("Chew"),
            publication("Daytripper"),
        )

        val continuous = listOf(
            LibrarySort.LAST_READ,
            LibrarySort.PROGRESS,
            LibrarySort.DATE_ADDED,
            LibrarySort.FILE_SIZE,
        )
        for (sort in continuous) assertTrue(divide(shelf, sort).isEmpty())
    }

    @Test
    fun `a series stays a heading under a sort that divides into nothing else`() {
        // "Divided by series where a publication declares one, and otherwise by the active
        // sort key" — series first, whatever the sort. The scatter rule is what stops that
        // from producing the same heading twice.
        val shelf = series("Ashfall", 4) + series("Blackwater", 4)

        assertEquals(
            listOf("Ashfall", "Blackwater"),
            divide(shelf, LibrarySort.LAST_READ).map { it.title },
        )
    }

    @Test
    fun `a shelf that divides into one section is not divided at all`() {
        assertTrue(divide(series("Ashfall", 8), LibrarySort.SERIES).isEmpty())
    }

    @Test
    fun `a division that does not average a row of covers a heading is refused`() {
        // Twenty-two unrelated files with a distinct initial each. Sectioning turns one dense
        // grid into a tall column of near-empty rows, every one announced — worse to read
        // than the wall it replaced. Seen on a booted simulator with the test corpus, which
        // is exactly this shelf.
        val shelf = "ABCDEFGHIJKLMNOPQRSTUV".map { publication("${it}ne of a kind") }

        assertEquals(22, shelf.size)
        assertTrue(divide(shelf, LibrarySort.TITLE).isEmpty())
    }

    @Test
    fun `the same shelf divides once its headings each cover a row and more`() {
        val shelf = series("Ashfall", 6) + series("Blackwater", 6) + series("Cinderfall", 6)

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals(listOf("Ashfall", "Blackwater", "Cinderfall"), sections.map { it.title })
    }

    @Test
    fun `an empty shelf divides into nothing rather than into an empty heading`() {
        assertTrue(divide(emptyList(), LibrarySort.TITLE).isEmpty())
    }

    @Test
    fun `dividing keeps every publication exactly once`() {
        // The one property that makes the whole thing safe: a shelf with headings holds the
        // same books as the shelf without them.
        val shelf = series("Ashfall", 5) +
            listOf(publication("Akira"), publication("Astro Boy"), publication("Blame")) +
            series("Blackwater", 5)

        val divided = divide(shelf, LibrarySort.SERIES)
            .flatMap { it.publications }
            .map { it.displayTitle }

        assertEquals(shelf.map { it.displayTitle }, divided)
    }

    @Test
    fun `a series the sort scatters is not a heading, because two of them are two places`() {
        // Sorted by title, "Ashfall #3" is filed under T and "Ashfall #4" under W, with other
        // books between them. Two sections headed "Ashfall" would read as the app having lost
        // half a series, so both fall back to the letter the sort filed them under.
        val shelf = listOf(
            publication("The Long Count", series = "Ashfall"),
            publication("The Third Chapter"),
            publication("The Quiet Season"),
            publication("Undeclared Direction"),
            publication("Unsupported Codec"),
            publication("Undertow"),
            publication("What the Courier Carried", series = "Ashfall"),
            publication("What Came After"),
            publication("Whiteout"),
        )

        val sections = divide(shelf, LibrarySort.TITLE)

        assertEquals(listOf("T", "U", "W"), sections.map { it.title })
    }

    @Test
    fun `a series the sort keeps together is still a heading`() {
        // The same publications, sorted by series: now they are adjacent, one heading covers
        // both, and the demotion above must not fire.
        val shelf = series("Ashfall", 4) + listOf(
            publication("Undeclared Direction"),
            publication("Unsupported Codec"),
            publication("Undertow"),
            publication("Whiteout"),
        )

        val sections = divide(shelf, LibrarySort.SERIES)

        assertEquals("Ashfall", sections.first().title)
        assertEquals(2, sections.size)
    }

    @Test
    fun `a series named only by whitespace is not a series`() {
        val shelf = listOf(
            publication("Akira", series = "  "),
            publication("Astro Boy", series = "  "),
            publication("Appleseed", series = "  "),
            publication("Berserk"),
            publication("Blame"),
            publication("Blacksad"),
        )

        val sections = divide(shelf, LibrarySort.TITLE)

        assertEquals(listOf("A", "B"), sections.map { it.title })
    }
}
