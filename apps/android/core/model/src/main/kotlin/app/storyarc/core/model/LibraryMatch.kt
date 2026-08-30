package app.storyarc.core.model

import java.util.Locale

/**
 * Why a publication answered a search.
 *
 * `library-browsing`: search results "are grouped by match kind — series, publication,
 * person, tag". The kind is the answer to "why is this here", and a reader who typed a word
 * that is both an author's name and half a title needs that answer to make sense of forty
 * rows.
 *
 * iOS's `MatchKind` mirrors it.
 */
enum class MatchKind {
    /** The query is in the series name. */
    SERIES,

    /** The query is in the title. */
    PUBLICATION,

    /** The query is in an author's name. */
    PERSON,

    /**
     * The query is in a tag-like value.
     *
     * Today that means the publisher and nothing else: a publication carries no tags and no
     * genres yet, so this group holds publisher matches. Named for what the requirement asks
     * for rather than for what is indexed, because the group is right and the corpus is what
     * will grow.
     */
    TAG,
}

/**
 * One heading's worth of search results.
 *
 * The publications inside stay in the order [LibraryIndex.arrange] put them, so grouping can
 * never disagree with ranking — a group is a partition of the ranked list, not a second
 * opinion about it.
 */
data class MatchGroup(val kind: MatchKind, val publications: List<Publication>)

/**
 * Search results, grouped by why each one matched.
 *
 * Empty when nothing was typed, and deliberately so: the caller draws the flat shelf then,
 * and a single group headed "Titles" over an unsearched library would be a heading that says
 * nothing.
 *
 * A publication appears in exactly one group — the kind of its *best* match. A title that
 * also contains the author's name is one book, and listing it twice would make the library
 * look bigger than it is.
 */
fun LibraryIndex.grouped(
    publications: List<Publication>,
    query: LibraryQuery,
    locale: Locale = Locale.getDefault(),
    progress: (Publication) -> LibraryIndex.Progress = { LibraryIndex.Progress.unread },
): List<MatchGroup> {
    val term = query.search.trim().lowercase(locale)
    if (term.isEmpty()) return emptyList()

    // Grouped out of the arranged list rather than out of the raw one: the filters, the
    // scope and the ranking have all already been applied, and re-deciding any of them here
    // is how two code paths start disagreeing.
    val ranked = arrange(publications, query, locale, progress)

    // Headings in the order their best match came, not in the order the enum is written. A
    // title that starts with what was typed outranks a series that merely contains it, and a
    // fixed heading order would bury the row the reader meant.
    val members = LinkedHashMap<MatchKind, MutableList<Publication>>()
    for (publication in ranked) {
        val rank = rank(publication, term, locale) ?: continue
        members.getOrPut(kindOfRank(rank)) { mutableListOf() }.add(publication)
    }
    return members.map { (kind, found) -> MatchGroup(kind, found) }
}

/**
 * Which group a rank belongs to.
 *
 * Ranks 0 and 1 are both the title — one starts with the query and one contains it — and
 * both are the same answer to "why is this here". The distinction between them is about
 * order, and order is already settled by the time this is asked.
 */
internal fun kindOfRank(rank: Int): MatchKind = when (rank) {
    0, 1 -> MatchKind.PUBLICATION
    2 -> MatchKind.SERIES
    3 -> MatchKind.PERSON
    else -> MatchKind.TAG
}
