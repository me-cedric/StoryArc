package app.storyarc.core.model

import java.text.Collator
import java.util.Locale

/**
 * Turns the whole library into the list on screen.
 *
 * Pure, and deliberately so: this is the part of `library-browsing` that has to
 * behave identically on both platforms, and it is the part worth asserting
 * against the same table in both test suites (ADR-0001). iOS's `LibraryIndex`
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

        // Narrowed to the scope before anything else is asked. `library-browsing`: with a
        // single source selected "the view, its search, and its filters apply to that source
        // alone", so nothing outside it should ever reach a filter to be judged.
        val kept = inScope(publications, query.scope).filter { publication ->
            keeps(publication, query, progress(publication).state) &&
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
     * The next publication in the same series.
     *
     * `comic-reader`: reaching the end of one volume offers the next. Matching is on
     * the series name and the issue number, which is all a local library knows — a
     * reading list carries its own order and will answer this differently when there
     * are reading lists.
     *
     * `null` when the publication names no series, when nothing follows it, or when
     * the next thing cannot be opened. Offering a publication that refuses to open
     * would be worse than offering nothing.
     */
    fun next(after: Publication, library: List<Publication>): Publication? {
        val series = after.series ?: return null
        val current = issueNumber(after)

        return library
            .filter {
                it.id != after.id &&
                    it.series == series &&
                    it.isOpenable &&
                    issueNumber(it) > current
            }
            .minByOrNull { issueNumber(it) }
    }

    /**
     * An issue number as a number, so #10 follows #9.
     *
     * A publication with no number sorts last, which keeps a one-off out of the
     * middle of a numbered run.
     */
    private fun issueNumber(publication: Publication): Double =
        publication.number?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull()
            ?: Double.MAX_VALUE

    /**
     * Whether a publication survives every filter group.
     *
     * `library-browsing`: the groups "combine with AND", so an empty group is no
     * opinion at all and any group holding values has to be satisfied. Within one
     * group the values are alternatives — two formats ticked means either.
     *
     * Its own function rather than a chain inside [arrange]: the chain is seven
     * groups long now, and iOS's `LibraryIndex.keeps` has to be readable against it
     * line for line (ADR-0001).
     */
    fun keeps(publication: Publication, query: LibraryQuery, state: ReadState): Boolean {
        /** A group over a value the publication has at most one of. */
        fun holds(chosen: Set<String>, value: String?) = chosen.isEmpty() || value in chosen

        /** A group over a value the publication can carry several of. */
        fun meets(chosen: Set<String>, values: List<String>) =
            chosen.isEmpty() || values.any { it in chosen }

        return (query.readStates.isEmpty() || state in query.readStates) &&
            (query.formats.isEmpty() || publication.format in query.formats) &&
            holds(query.languages, publication.language) &&
            holds(query.publishers, publication.publisher) &&
            meets(query.genres, publication.genres) &&
            meets(query.tags, publication.tags) &&
            query.years.contains(publication.year)
    }

    /**
     * How well a publication answers the query, lower being better, or `null` for
     * no match at all.
     *
     * A title that starts with what was typed is what the user meant far more
     * often than an author whose name contains it somewhere.
     */
    /** Internal, not private: [LibraryMatch] groups results by *why* they matched and asks
     * this for the reason. */
    internal fun rank(publication: Publication, term: String, locale: Locale): Int? {
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

        // Newest first, the same way as YEAR and LAST_READ: for a date, the
        // interesting end of the list is the recent one, and a reader asking for
        // what they added lately does not want 2019 at the top.
        LibrarySort.DATE_ADDED ->
            -(left.addedAtEpochMillis ?: 0L).compareTo(right.addedAtEpochMillis ?: 0L)

        // Largest first, for the same reason PROGRESS puts the most-read first: the
        // reason to sort by size is to find what is taking up the disk.
        LibrarySort.FILE_SIZE -> -(left.fileSize ?: 0L).compareTo(right.fileSize ?: 0L)
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
