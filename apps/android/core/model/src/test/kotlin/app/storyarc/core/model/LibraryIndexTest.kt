package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Locale

/**
 * The browsing rules, asserted against the same table as iOS's
 * `LibraryIndexTests`.
 *
 * `library-browsing` has to behave identically on both platforms, and two
 * independent implementations (ADR-0001) only stay honest if the same cases are
 * put to both. Add a case here, add it there.
 */
class LibraryIndexTest {

    private fun publication(
        title: String,
        series: String? = null,
        number: String? = null,
        authors: List<String> = emptyList(),
        format: PublicationFormat = PublicationFormat.CBZ,
        publisher: String? = null,
        year: Int? = null,
        language: String? = null,
        genres: List<String> = emptyList(),
        tags: List<String> = emptyList(),
        fileSize: Long? = null,
        addedAtEpochMillis: Long? = null,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title"),
        format = format,
        displayTitle = title,
        series = series,
        number = number,
        authors = authors,
        publisher = publisher,
        year = year,
        language = language,
        genres = genres,
        tags = tags,
        origin = MetadataOrigin.INFERRED,
        fileSize = fileSize,
        addedAtEpochMillis = addedAtEpochMillis,
    )

    private fun titles(publications: List<Publication>) = publications.map { it.displayTitle }

    // Leading articles.

    @Test
    fun `an English leading article does not decide where a title files`() {
        assertEquals("Sandman", LibraryIndex.sortKey("The Sandman", Locale.ENGLISH))
        assertEquals("Contract with God", LibraryIndex.sortKey("A Contract with God", Locale.ENGLISH))
    }

    @Test
    fun `an article in another language is left alone`() {
        // "La" is an article in Spanish and part of the name in English.
        assertEquals("La Brea", LibraryIndex.sortKey("La Brea", Locale.ENGLISH))
        assertEquals("Brea", LibraryIndex.sortKey("La Brea", Locale.of("es")))
    }

    @Test
    fun `the French apostrophe form carries no space`() {
        assertEquals("Étranger", LibraryIndex.sortKey("L'Étranger", Locale.FRENCH))
    }

    @Test
    fun `a title that is only an article keeps it`() {
        assertEquals("The", LibraryIndex.sortKey("The", Locale.ENGLISH))
    }

    // Sorting.

    @Test
    fun `titles sort by their key, not their first letter`() {
        val library = listOf(publication("The Sandman"), publication("Akira"), publication("Bone"))
        val sorted = LibraryIndex.arrange(library, LibraryQuery(), Locale.ENGLISH)
        assertEquals(listOf("Akira", "Bone", "The Sandman"), titles(sorted))
    }

    @Test
    fun `descending reverses the order`() {
        val library = listOf(publication("Akira"), publication("Bone"))
        val sorted = LibraryIndex.arrange(
            library,
            LibraryQuery(sort = LibrarySort.TITLE, ascending = false),
            Locale.ENGLISH,
        )
        assertEquals(listOf("Bone", "Akira"), titles(sorted))
    }

    @Test
    fun `a series sorts by issue number, numerically`() {
        val library = listOf(
            publication("Bone #10", series = "Bone", number = "10"),
            publication("Bone #9", series = "Bone", number = "9"),
            publication("Bone #2", series = "Bone", number = "2"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("Bone #2", "Bone #9", "Bone #10"), titles(sorted))
    }

    @Test
    fun `date added puts the newest first, and never-dated last`() {
        val library = listOf(
            publication("Maus"),
            publication("Bone", addedAtEpochMillis = 100L),
            publication("Akira", addedAtEpochMillis = 300L),
        )
        val sorted = LibraryIndex.arrange(
            library,
            LibraryQuery(sort = LibrarySort.DATE_ADDED),
            Locale.ENGLISH,
        )
        assertEquals(listOf("Akira", "Bone", "Maus"), titles(sorted))
    }

    @Test
    fun `file size puts the largest first, and unweighed last`() {
        val library = listOf(
            publication("Maus"),
            publication("Bone", fileSize = 100L),
            publication("Akira", fileSize = 300L),
        )
        val sorted = LibraryIndex.arrange(
            library,
            LibraryQuery(sort = LibrarySort.FILE_SIZE),
            Locale.ENGLISH,
        )
        assertEquals(listOf("Akira", "Bone", "Maus"), titles(sorted))
    }

    // Search.

    @Test
    fun `a title that starts with the query outranks an author who contains it`() {
        val library = listOf(
            publication("Watchmen", authors = listOf("Alan Moore")),
            publication("Alan's Diary", authors = listOf("Someone Else")),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(search = "alan"), Locale.ENGLISH)
        assertEquals(listOf("Alan's Diary", "Watchmen"), titles(sorted))
    }

    @Test
    fun `a query that matches nothing returns nothing rather than everything`() {
        val library = listOf(publication("Akira"), publication("Bone"))
        assertEquals(emptyList<String>(), titles(LibraryIndex.arrange(library, LibraryQuery(search = "zzz"))))
    }

    // Filters.

    @Test
    fun `filters combine with AND`() {
        val library = listOf(
            publication("Akira", format = PublicationFormat.CBZ),
            publication("Bone", format = PublicationFormat.PDF),
        )
        val query = LibraryQuery(formats = setOf(PublicationFormat.CBZ), search = "o")
        assertEquals(emptyList<String>(), titles(LibraryIndex.arrange(library, query, Locale.ENGLISH)))
    }

    @Test
    fun `a filter group counts once however many values it holds`() {
        val query = LibraryQuery(
            formats = setOf(PublicationFormat.CBZ, PublicationFormat.CBR, PublicationFormat.PDF),
            readStates = setOf(ReadState.UNREAD),
        )
        assertEquals(2, query.activeFilterCount)
    }

    @Test
    fun `every group counts, and the year range counts once for both its ends`() {
        val query = LibraryQuery(
            readStates = setOf(ReadState.UNREAD),
            formats = setOf(PublicationFormat.CBZ),
            languages = setOf("en"),
            publishers = setOf("DC"),
            genres = setOf("Superhero"),
            tags = setOf("Reprint"),
            years = YearRange(from = 1986, to = 1999),
        )
        assertEquals(7, query.activeFilterCount)
    }

    @Test
    fun `clearing keeps the search and the sort and drops every group`() {
        val query = LibraryQuery(
            search = "bone",
            readStates = setOf(ReadState.UNREAD),
            formats = setOf(PublicationFormat.CBZ),
            languages = setOf("en"),
            publishers = setOf("DC"),
            genres = setOf("Superhero"),
            tags = setOf("Reprint"),
            years = YearRange(from = 1986),
            sort = LibrarySort.LAST_READ,
            ascending = false,
        )
        val cleared = query.withoutFilters()
        assertEquals(0, cleared.activeFilterCount)
        assertEquals("bone", cleared.search)
        assertEquals(LibrarySort.LAST_READ, cleared.sort)
        assertEquals(false, cleared.ascending)
    }

    @Test
    fun `a publisher filter keeps only what that publisher put out`() {
        val library = listOf(
            publication("Watchmen", publisher = "DC"),
            publication("Akira", publisher = "Kodansha"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(publishers = setOf("DC")), Locale.ENGLISH)
        assertEquals(listOf("Watchmen"), titles(sorted))
    }

    @Test
    fun `two publishers ticked means either, not both`() {
        val library = listOf(
            publication("Watchmen", publisher = "DC"),
            publication("Akira", publisher = "Kodansha"),
            publication("Bone", publisher = "Cartoon Books"),
        )
        val query = LibraryQuery(publishers = setOf("DC", "Kodansha"))
        assertEquals(listOf("Akira", "Watchmen"), titles(LibraryIndex.arrange(library, query, Locale.ENGLISH)))
    }

    @Test
    fun `a language filter keeps only that language`() {
        val library = listOf(
            publication("Akira", language = "ja"),
            publication("Bone", language = "en"),
        )
        val query = LibraryQuery(languages = setOf("ja"))
        assertEquals(listOf("Akira"), titles(LibraryIndex.arrange(library, query, Locale.ENGLISH)))
    }

    @Test
    fun `a genre filter keeps a publication that carries the genre among others`() {
        val library = listOf(
            publication("Watchmen", genres = listOf("Superhero", "Mystery")),
            publication("Maus", genres = listOf("Biography")),
        )
        val query = LibraryQuery(genres = setOf("Mystery"))
        assertEquals(listOf("Watchmen"), titles(LibraryIndex.arrange(library, query, Locale.ENGLISH)))
    }

    @Test
    fun `genre and tag are separate groups, so they combine with AND`() {
        val both = publication("Watchmen", genres = listOf("Superhero"), tags = listOf("Reprint"))
        val genreOnly = publication("Batman", genres = listOf("Superhero"), tags = listOf("Annual"))
        val query = LibraryQuery(genres = setOf("Superhero"), tags = setOf("Reprint"))
        val sorted = LibraryIndex.arrange(listOf(both, genreOnly), query, Locale.ENGLISH)
        assertEquals(listOf("Watchmen"), titles(sorted))
    }

    @Test
    fun `a year range keeps what came out inside it, both ends included`() {
        val library = listOf(
            publication("Watchmen", year = 1986),
            publication("Bone", year = 1991),
            publication("Persepolis", year = 2000),
        )
        val query = LibraryQuery(years = YearRange(from = 1986, to = 1991))
        assertEquals(listOf("Bone", "Watchmen"), titles(LibraryIndex.arrange(library, query, Locale.ENGLISH)))
    }

    @Test
    fun `one end of a range is enough`() {
        val library = listOf(publication("Watchmen", year = 1986), publication("Persepolis", year = 2000))
        val from = LibraryIndex.arrange(library, LibraryQuery(years = YearRange(from = 1990)), Locale.ENGLISH)
        assertEquals(listOf("Persepolis"), titles(from))
        val upTo = LibraryIndex.arrange(library, LibraryQuery(years = YearRange(to = 1990)), Locale.ENGLISH)
        assertEquals(listOf("Watchmen"), titles(upTo))
    }

    @Test
    fun `a publication with no year is outside an active range, not before it`() {
        val library = listOf(publication("Undated"), publication("Watchmen", year = 1986))
        val query = LibraryQuery(years = YearRange(to = 2000))
        assertEquals(listOf("Watchmen"), titles(LibraryIndex.arrange(library, query, Locale.ENGLISH)))
        // And still there when no range is set, which is what "no opinion" means.
        assertEquals(2, LibraryIndex.arrange(library, LibraryQuery(), Locale.ENGLISH).size)
    }

    @Test
    fun `every group narrows the same list at once`() {
        val match = publication(
            "Watchmen",
            format = PublicationFormat.CBZ,
            publisher = "DC",
            year = 1986,
            language = "en",
            genres = listOf("Superhero"),
            tags = listOf("Reprint"),
        )
        // Identical but for the publisher, which is enough to drop it.
        val miss = publication(
            "Watchmen Companion",
            format = PublicationFormat.CBZ,
            publisher = "Marvel",
            year = 1986,
            language = "en",
            genres = listOf("Superhero"),
            tags = listOf("Reprint"),
        )
        val query = LibraryQuery(
            formats = setOf(PublicationFormat.CBZ),
            languages = setOf("en"),
            publishers = setOf("DC"),
            genres = setOf("Superhero"),
            tags = setOf("Reprint"),
            years = YearRange(from = 1980, to = 1989),
        )
        assertEquals(listOf("Watchmen"), titles(LibraryIndex.arrange(listOf(match, miss), query, Locale.ENGLISH)))
    }

    @Test
    fun `read state filters on what the progress store says`() {
        val akira = publication("Akira")
        val bone = publication("Bone")
        val states = mapOf(
            akira.id to LibraryIndex.Progress(ReadState.FINISHED, 1.0, 10L),
            bone.id to LibraryIndex.Progress(ReadState.IN_PROGRESS, 0.5, 20L),
        )
        val sorted = LibraryIndex.arrange(
            listOf(akira, bone),
            LibraryQuery(readStates = setOf(ReadState.IN_PROGRESS)),
            Locale.ENGLISH,
        ) { states[it.id] ?: LibraryIndex.Progress.unread }
        assertEquals(listOf("Bone"), titles(sorted))
    }


    // Next in series.

    @Test
    fun `the next issue is the one after this number, not the next row`() {
        val second = publication("Bone #2", series = "Bone", number = "2")
        val library = listOf(
            publication("Bone #10", series = "Bone", number = "10"),
            second,
            publication("Bone #9", series = "Bone", number = "9"),
            publication("Akira", series = "Akira", number = "1"),
        )
        assertEquals("Bone #9", LibraryIndex.next(second, library)?.displayTitle)
    }

    @Test
    fun `the last issue in a series has no next`() {
        val last = publication("Bone #2", series = "Bone", number = "2")
        val library = listOf(publication("Bone #1", series = "Bone", number = "1"), last)
        assertNull(LibraryIndex.next(last, library))
    }

    @Test
    fun `a publication with no series has no next, however many neighbours it has`() {
        val alone = publication("Watchmen")
        assertNull(LibraryIndex.next(alone, listOf(alone, publication("Akira"))))
    }

    // Continue reading.

    @Test
    fun `continue reading holds only what is in progress, most recent first`() {
        val akira = publication("Akira")
        val bone = publication("Bone")
        val maus = publication("Maus")
        val states = mapOf(
            akira.id to LibraryIndex.Progress(ReadState.IN_PROGRESS, 0.2, 100L),
            bone.id to LibraryIndex.Progress(ReadState.IN_PROGRESS, 0.8, 300L),
            maus.id to LibraryIndex.Progress(ReadState.FINISHED, 1.0, 400L),
        )
        val row = LibraryIndex.continueReading(listOf(akira, bone, maus)) {
            states[it.id] ?: LibraryIndex.Progress.unread
        }
        assertEquals(listOf("Bone", "Akira"), titles(row))
    }

    @Test
    fun `continue reading is empty rather than a header over a gap`() {
        val library = listOf(publication("Akira"))
        assertEquals(
            emptyList<String>(),
            titles(LibraryIndex.continueReading(library) { LibraryIndex.Progress.unread }),
        )
    }
}
