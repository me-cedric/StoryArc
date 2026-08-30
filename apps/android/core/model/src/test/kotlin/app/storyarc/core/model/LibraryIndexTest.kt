package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale
import java.util.UUID

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
        publisher: String? = null,
        format: PublicationFormat = PublicationFormat.CBZ,
        year: Int? = null,
        language: String? = null,
        genres: List<String> = emptyList(),
        tags: List<String> = emptyList(),
        fileSize: Long? = null,
        addedAtEpochMillis: Long? = null,
        source: UUID? = null,
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
        sourceId = source,
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
    fun `a publication with no series sorts after every publication that has one`() {
        // "Zephyr" used to sort by its title *among* the series names, landing between
        // "Ashfall" and "Blackwater" — which splits the standalone pile in two and stops a
        // sectioned shelf from dividing at all.
        val library = listOf(
            publication("Blackwater #1", series = "Blackwater", number = "1"),
            publication("Zephyr"),
            publication("Ashfall #2", series = "Ashfall", number = "2"),
            publication("Ashfall #1", series = "Ashfall", number = "1"),
            publication("Almanac"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(
            listOf("Ashfall #1", "Ashfall #2", "Blackwater #1", "Almanac", "Zephyr"),
            titles(sorted),
        )
    }

    @Test
    fun `an empty series and a whitespace series are both no series`() {
        // A real `ComicInfo.xml` writes all three for a book that belongs to no series.
        val library = listOf(
            publication("Blank", series = ""),
            publication("Ashfall #1", series = "Ashfall", number = "1"),
            publication("Spaces", series = "   "),
            publication("Absent"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("Ashfall #1", "Absent", "Blank", "Spaces"), titles(sorted))
    }

    @Test
    fun `descending keeps the standalones together, at the other end`() {
        // The pile has to stay one contiguous run whichever way the shelf runs, because
        // that is what lets it be drawn under a single heading.
        val library = listOf(
            publication("Ashfall #1", series = "Ashfall", number = "1"),
            publication("Zephyr"),
            publication("Blackwater #1", series = "Blackwater", number = "1"),
            publication("Almanac"),
        )
        val sorted = LibraryIndex.arrange(
            library,
            LibraryQuery(sort = LibrarySort.SERIES, ascending = false),
            Locale.ENGLISH,
        )
        assertEquals(listOf("Zephyr", "Almanac", "Blackwater #1", "Ashfall #1"), titles(sorted))
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

    // Previous in series.

    @Test
    fun `the previous issue is the one before this number, not the row above`() {
        val tenth = publication("Bone #10", series = "Bone", number = "10")
        val library = listOf(
            tenth,
            publication("Bone #2", series = "Bone", number = "2"),
            publication("Bone #9", series = "Bone", number = "9"),
            publication("Akira", series = "Akira", number = "1"),
        )
        assertEquals("Bone #9", LibraryIndex.previous(tenth, library)?.displayTitle)
    }

    @Test
    fun `the first issue in a series has no previous`() {
        val first = publication("Bone #1", series = "Bone", number = "1")
        val library = listOf(first, publication("Bone #2", series = "Bone", number = "2"))
        assertNull(LibraryIndex.previous(first, library))
    }

    @Test
    fun `a publication with no series has no previous either`() {
        val alone = publication("Watchmen")
        assertNull(LibraryIndex.previous(alone, listOf(alone, publication("Akira"))))
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

    // Scope.

    private val folder = UUID.randomUUID()
    private val server = UUID.randomUUID()

    private fun mixedLibrary() = listOf(
        publication("Akira", source = folder),
        publication("Bone", source = server),
        publication("Maus"),
    )

    @Test
    fun `the library spans every source until it is narrowed to one`() {
        val sorted = LibraryIndex.arrange(mixedLibrary(), LibraryQuery(), Locale.ENGLISH)
        assertEquals(listOf("Akira", "Bone", "Maus"), titles(sorted))
    }

    @Test
    fun `a scope shows one source and hides the rest`() {
        val query = LibraryQuery(scope = LibraryScope.OneSource(server))
        assertEquals(
            listOf("Bone"),
            titles(LibraryIndex.arrange(mixedLibrary(), query, Locale.ENGLISH)),
        )
    }

    @Test
    fun `a scope narrows the search as well as the shelf`() {
        // "o" is in Bone and in Maus... and only Bone is on the server.
        val query = LibraryQuery(search = "o", scope = LibraryScope.OneSource(server))
        assertEquals(
            listOf("Bone"),
            titles(LibraryIndex.arrange(mixedLibrary(), query, Locale.ENGLISH)),
        )
    }

    @Test
    fun `a publication no source claims belongs only to the whole library`() {
        val orphan = publication("Maus")
        assertTrue(LibraryScope.AllSources.contains(orphan))
        assertFalse(LibraryScope.OneSource(folder).contains(orphan))
    }

    @Test
    fun `a scope survives a round trip through storage`() {
        assertEquals("all", LibraryScope.AllSources.storageKey)
        assertEquals(LibraryScope.AllSources, LibraryScope.of("all"))

        val scoped = LibraryScope.OneSource(server)
        assertEquals(scoped, LibraryScope.of(scoped.storageKey))
    }

    @Test
    fun `a stored scope naming nothing recognisable opens the whole library`() {
        // Never an empty shelf with nothing to explain it: the reader did not remove
        // anything they can see, and "all sources" is the answer that is never wrong.
        assertEquals(LibraryScope.AllSources, LibraryScope.of("not-a-uuid"))
        assertEquals(LibraryScope.AllSources, LibraryScope.of(null))

        val registry = SourceRegistry(
            sources = listOf(Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER)),
        )
        assertEquals(
            LibraryScope.AllSources,
            LibraryScope.OneSource(server).resolved(registry),
        )
    }

    @Test
    fun `a scope whose source is still there is left alone`() {
        val source = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER)
        val registry = SourceRegistry(sources = listOf(source))
        assertEquals(
            LibraryScope.OneSource(source.id),
            LibraryScope.OneSource(source.id).resolved(registry),
        )
    }

    @Test
    fun `a source is named on a row only when there is more than one`() {
        val one = Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER)
        val two = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER)

        assertFalse(SourceRegistry(sources = listOf(one)).attributesPublications)
        assertTrue(SourceRegistry(sources = listOf(one, two)).attributesPublications)
        assertEquals("Kavita", SourceRegistry(sources = listOf(one, two)).nameOf(two.id))
        assertNull(SourceRegistry(sources = listOf(one, two)).nameOf(null))
    }

    @Test
    fun `the scopes on offer are every source, in the reader's own order`() {
        val one = Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER)
        val two = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER)
        assertEquals(
            listOf(
                LibraryScope.AllSources,
                LibraryScope.OneSource(one.id),
                LibraryScope.OneSource(two.id),
            ),
            SourceRegistry(sources = listOf(one, two)).scopes,
        )
    }

    // Search grouping.

    @Test
    fun `results are grouped by why they matched`() {
        val library = listOf(
            publication("Sandman Mystery Theatre"),
            publication("Preludes", series = "The Sandman"),
            publication("Endless Nights", publisher = "Sandman Press"),
        )
        val groups = LibraryIndex.grouped(
            library,
            LibraryQuery(search = "sandman"),
            Locale.ENGLISH,
        )

        assertEquals(
            listOf(MatchKind.PUBLICATION, MatchKind.SERIES, MatchKind.TAG),
            groups.map { it.kind },
        )
        assertEquals(listOf("Sandman Mystery Theatre"), titles(groups[0].publications))
        assertEquals(listOf("Preludes"), titles(groups[1].publications))
        assertEquals(listOf("Endless Nights"), titles(groups[2].publications))
    }

    @Test
    fun `an author match is a person, and headings follow the best match`() {
        val library = listOf(
            publication("Signal to Noise", authors = listOf("Neil Gaiman")),
            publication("Gaiman Reader"),
        )
        val groups = LibraryIndex.grouped(
            library,
            LibraryQuery(search = "gaiman"),
            Locale.ENGLISH,
        )
        assertEquals(listOf(MatchKind.PUBLICATION, MatchKind.PERSON), groups.map { it.kind })
    }

    @Test
    fun `a publication that matches twice appears once, under its best match`() {
        val library = listOf(publication("Alan's Diary", authors = listOf("Alan Moore")))
        val groups = LibraryIndex.grouped(library, LibraryQuery(search = "alan"), Locale.ENGLISH)
        assertEquals(listOf(MatchKind.PUBLICATION), groups.map { it.kind })
        assertEquals(1, groups.flatMap { it.publications }.size)
    }

    @Test
    fun `nothing typed means no headings rather than one saying Titles`() {
        assertEquals(
            emptyList<MatchGroup>(),
            LibraryIndex.grouped(mixedLibrary(), LibraryQuery(), Locale.ENGLISH),
        )
    }

    @Test
    fun `grouping obeys the scope, because it groups what the shelf already shows`() {
        val library = listOf(
            publication("Bone", source = folder),
            publication("Bone Sharps", source = server),
        )
        val query = LibraryQuery(search = "bone", scope = LibraryScope.OneSource(server))
        val groups = LibraryIndex.grouped(library, query, Locale.ENGLISH)
        assertEquals(listOf("Bone Sharps"), groups.flatMap { titles(it.publications) })
    }
}
