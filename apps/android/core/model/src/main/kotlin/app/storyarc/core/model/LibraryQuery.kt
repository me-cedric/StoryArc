package app.storyarc.core.model

import java.text.Collator
import java.util.Locale

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
 * What the user is looking at, and in what order.
 *
 * One value rather than five pieces of view state, so "return to the library and
 * the filters are still applied" is one thing to keep and one thing to restore.
 */
data class LibraryQuery(
    val search: String = "",
    val readStates: Set<ReadState> = emptySet(),
    val formats: Set<PublicationFormat> = emptySet(),
    val languages: Set<String> = emptySet(),
    val sort: LibrarySort = LibrarySort.TITLE,
    val ascending: Boolean = true,
) {
    /**
     * What the filter control shows as a badge.
     *
     * A group counts once however many values it holds: three formats is one
     * decision the user made, and a badge reading "5" for it would misdescribe
     * how much has to be undone.
     */
    val activeFilterCount: Int
        get() = listOf(readStates, formats, languages).count { it.isNotEmpty() }

    val hasFilters: Boolean get() = activeFilterCount > 0

    /** Whether anything at all is narrowing the view, search included. */
    val isNarrowed: Boolean get() = hasFilters || search.isNotBlank()
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

/**
 * Turns the whole library into the list on screen.
 *
 * Pure, and deliberately so: this is the part of `library-browsing` that has to
 * behave identically on both platforms, and it is the part worth asserting
 * against the same table in both test suites (ADR-0001). iOS's `LibraryQuery`
 * mirrors it line for line.
 *
 * Not here yet, and named rather than silently missing: grouping results by match
 * kind, merging a server's own search with local results, and the curated order
 * of a reading list. All three need a second source or a collection to exist.
 */
object LibraryIndex {

    /** What the library knows about a publication's progress. */
    data class Progress(
        val state: ReadState,
        val fraction: Double,
        val lastReadEpochMillis: Long?,
    ) {
        companion object {
            val unread = Progress(ReadState.UNREAD, 0.0, null)

            fun of(record: ReadingProgress?): Progress {
                if (record == null) return unread
                val fraction = if (record.isFinished) 1.0 else record.position.fraction
                val state = when {
                    record.isFinished -> ReadState.FINISHED
                    fraction > 0.0 -> ReadState.IN_PROGRESS
                    else -> ReadState.UNREAD
                }
                return Progress(state, fraction, record.updatedAtEpochMillis)
            }
        }
    }

    /**
     * The filtered, ranked and sorted list.
     *
     * Ranking only applies while a search is running: with a query, how well a
     * publication matches is more useful than the sort field, and the sort breaks
     * ties within each rank.
     */
    fun arrange(
        publications: List<Publication>,
        query: LibraryQuery,
        locale: Locale = Locale.getDefault(),
        progress: (Publication) -> Progress = { Progress.unread },
    ): List<Publication> {
        val term = query.search.trim().lowercase(locale)
        val collator = Collator.getInstance(locale).apply { strength = Collator.SECONDARY }

        val kept = publications.filter { publication ->
            val record = progress(publication)
            (query.readStates.isEmpty() || record.state in query.readStates) &&
                (query.formats.isEmpty() || publication.format in query.formats) &&
                (query.languages.isEmpty() || publication.language in query.languages) &&
                (term.isEmpty() || rank(publication, term, locale) != null)
        }

        val ordered = kept.sortedWith { left, right ->
            if (term.isNotEmpty()) {
                val byRank = (rank(left, term, locale) ?: Int.MAX_VALUE)
                    .compareTo(rank(right, term, locale) ?: Int.MAX_VALUE)
                if (byRank != 0) return@sortedWith byRank
            }
            val byField = compare(left, right, query.sort, collator, locale, progress)
            if (byField != 0) {
                if (query.ascending) byField else -byField
            } else {
                // A stable tiebreak, always ascending: a list that reshuffles
                // equal rows when the direction flips looks broken.
                collator.compare(sortKey(left.displayTitle, locale), sortKey(right.displayTitle, locale))
            }
        }
        return ordered
    }

    /**
     * In-progress publications, most recently read first.
     *
     * `library-browsing`: the continue row "is absent, rather than shown empty,
     * when nothing is in progress" — so this returns an empty list and the caller
     * draws nothing, rather than a header over a gap.
     */
    fun continueReading(
        publications: List<Publication>,
        limit: Int = 12,
        progress: (Publication) -> Progress,
    ): List<Publication> =
        publications
            .mapNotNull { publication ->
                val record = progress(publication)
                if (record.state == ReadState.IN_PROGRESS) publication to record else null
            }
            .sortedByDescending { it.second.lastReadEpochMillis ?: 0L }
            .take(limit)
            .map { it.first }

    /**
     * How well a publication answers the query, lower being better, or `null` for
     * no match at all.
     *
     * A title that starts with what was typed is what the user meant far more
     * often than an author whose name contains it somewhere.
     */
    private fun rank(publication: Publication, term: String, locale: Locale): Int? {
        fun has(value: String?) = value?.lowercase(locale)?.contains(term) == true
        val title = publication.displayTitle.lowercase(locale)
        return when {
            title.startsWith(term) -> 0
            title.contains(term) -> 1
            has(publication.series) -> 2
            publication.authors.any { has(it) } -> 3
            has(publication.publisher) -> 4
            else -> null
        }
    }

    private fun compare(
        left: Publication,
        right: Publication,
        sort: LibrarySort,
        collator: Collator,
        locale: Locale,
        progress: (Publication) -> Progress,
    ): Int = when (sort) {
        LibrarySort.TITLE ->
            collator.compare(sortKey(left.displayTitle, locale), sortKey(right.displayTitle, locale))

        LibrarySort.SERIES -> {
            val bySeries = collator.compare(
                sortKey(left.series ?: left.displayTitle, locale),
                sortKey(right.series ?: right.displayTitle, locale),
            )
            // Within a series, the issue number decides — and numerically, so #10
            // follows #9 rather than #1.
            if (bySeries != 0) bySeries else numberOf(left).compareTo(numberOf(right))
        }

        // Never read sorts last whichever way the list runs: a row with no date is
        // not "the oldest", it is absent from the ordering the user asked for.
        LibrarySort.LAST_READ ->
            -(progress(left).lastReadEpochMillis ?: 0L).compareTo(progress(right).lastReadEpochMillis ?: 0L)

        LibrarySort.PROGRESS -> -progress(left).fraction.compareTo(progress(right).fraction)

        LibrarySort.YEAR -> -(left.year ?: 0).compareTo(right.year ?: 0)
    }

    private fun numberOf(publication: Publication): Double =
        publication.number?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull() ?: Double.MAX_VALUE

    /**
     * A title as it should be alphabetised.
     *
     * `library-browsing` requires leading articles in the interface language to be
     * ignored, so "The Sandman" files under S. The list is per language because
     * "la" is an article in French and Spanish and a syllable in English, and
     * stripping it from an English title would file "La Brea" under B.
     */
    fun sortKey(title: String, locale: Locale = Locale.getDefault()): String {
        val trimmed = title.trim()
        val articles = ARTICLES[locale.language] ?: emptySet()
        for (article in articles) {
            // The apostrophe forms — French "l'" — carry no space after them.
            if (article.endsWith("'")) {
                if (trimmed.length > article.length && trimmed.startsWith(article, ignoreCase = true)) {
                    return trimmed.substring(article.length).trim()
                }
                continue
            }
            val prefix = "$article "
            if (trimmed.length > prefix.length && trimmed.startsWith(prefix, ignoreCase = true)) {
                return trimmed.substring(prefix.length).trim()
            }
        }
        return trimmed
    }

    /** The four interface languages StoryArc ships. */
    private val ARTICLES = mapOf(
        "en" to setOf("the", "a", "an"),
        "fr" to setOf("le", "la", "les", "un", "une", "des", "l'"),
        "de" to setOf("der", "die", "das", "ein", "eine"),
        "es" to setOf("el", "la", "los", "las", "un", "una"),
    )
}
