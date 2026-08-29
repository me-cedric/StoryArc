package app.storyarc.core.model

/** How far through a publication the reader got, as the library thinks of it. */
enum class ReadState {
    UNREAD,
    IN_PROGRESS,
    FINISHED,
}

/**
 * What the library is ordered by.
 *
 * `library-browsing` also lists date added and file size. Neither is recorded
 * yet — a scan does not write down when it first saw a file, and the archive
 * layer reports page sizes rather than a file size. They are absent rather than
 * present and wrong.
 */
enum class LibrarySort {
    TITLE,
    SERIES,
    LAST_READ,
    PROGRESS,
    YEAR,
}

/**
 * The years a publication may have been released in.
 *
 * `library-browsing` asks for a year *range* rather than a set of years, so this is
 * a pair of bounds and not another `Set`. Either end may be absent: "since 1986"
 * and "up to 1999" are both things a reader means, and requiring both would make
 * the filter harder to set than to ignore.
 */
data class YearRange(val from: Int? = null, val to: Int? = null) {
    /** Whether the range narrows anything. One bound is enough. */
    val isActive: Boolean get() = from != null || to != null

    /**
     * Whether a publication's year falls inside.
     *
     * A publication with no year is **outside** an active range. It is not "before
     * everything" — the library simply does not know when it came out, and
     * answering a question about years with a book that has none would put noise in
     * every result the filter is meant to remove.
     */
    fun contains(year: Int?): Boolean {
        if (!isActive) return true
        if (year == null) return false
        if (from != null && year < from) return false
        if (to != null && year > to) return false
        return true
    }
}

/**
 * What the user is looking at, and in what order.
 *
 * One value rather than a dozen pieces of view state, so "return to the library and
 * the filters are still applied" is one thing to keep and one thing to restore.
 *
 * Seven of the ten facets `library-browsing` names are here: read state, format,
 * language, publisher, genre, tag and year range. The other three are absent rather
 * than half-built, and the spec's own Open Questions say why — download state needs
 * the library to know what has been downloaded, source belongs to the scope
 * selector the same spec asks for, and no format this app reads states a
 * publication status at all.
 */
data class LibraryQuery(
    val search: String = "",
    val readStates: Set<ReadState> = emptySet(),
    val formats: Set<PublicationFormat> = emptySet(),
    val languages: Set<String> = emptySet(),
    /**
     * Publishers, as the publication spells them. Not normalised: "DC" and "DC
     * Comics" are two publishers to a file, and pretending otherwise would drop
     * books out of a filter the reader set.
     */
    val publishers: Set<String> = emptySet(),
    val genres: Set<String> = emptySet(),
    val tags: Set<String> = emptySet(),
    val years: YearRange = YearRange(),
    val sort: LibrarySort = LibrarySort.TITLE,
    val ascending: Boolean = true,
) {
    /**
     * What the filter control shows as a badge.
     *
     * A group counts once however many values it holds: three formats is one
     * decision the user made, and a badge reading "5" for it would misdescribe
     * how much has to be undone. The year range is one group whichever of its two
     * ends the reader set, for the same reason.
     */
    val activeFilterCount: Int
        get() = listOf(readStates, formats, languages, publishers, genres, tags)
            .count { it.isNotEmpty() } + if (years.isActive) 1 else 0

    val hasFilters: Boolean get() = activeFilterCount > 0

    /** Whether anything at all is narrowing the view, search included. */
    val isNarrowed: Boolean get() = hasFilters || search.isNotBlank()

    /**
     * Every filter off, the search and the sort untouched.
     *
     * `library-browsing`: an empty-looking library must say filters are active and
     * offer one action to clear them. Here rather than in the view model so the two
     * platforms clear the same set — a facet added to one and forgotten in the
     * other's clear-all is exactly the drift ADR-0001 makes us watch for.
     */
    fun withoutFilters(): LibraryQuery = copy(
        readStates = emptySet(),
        formats = emptySet(),
        languages = emptySet(),
        publishers = emptySet(),
        genres = emptySet(),
        tags = emptySet(),
        years = YearRange(),
    )
}

/**
 * How publications are drawn.
 *
 * `library-browsing` requires both: a cover grid, and a compact list for a library
 * too large to recognise by artwork alone.
 */
enum class LibraryLayout {
    GRID,
    LIST,
}
