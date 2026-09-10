package app.storyarc.feature.library

import app.storyarc.core.model.Publication

/**
 * One row of the library: a publication, or a series holding several.
 *
 * `library-browsing`: "the library lists that series once, as a single cell carrying the
 * series' own artwork and how many publications it holds", and "a publication that belongs
 * to no series is a row of its own".
 */
internal sealed interface LibraryRow {

    /** Stable across arrangements, so a row keeps its place in a list that re-sorts. */
    val id: String

    /** The cover this row draws, and what a tap opens when the row holds one thing. */
    val lead: Publication

    /** A publication with no series, or the only one its series has. */
    data class One(override val lead: Publication) : LibraryRow {
        override val id: String get() = lead.id
    }

    /** A series, and the publications inside it in the order the library arranged them. */
    data class Series(
        val name: String,
        val members: List<Publication>,
    ) : LibraryRow {
        override val id: String get() = "series:$name"
        override val lead: Publication get() = members.first()
        val count: Int get() = members.size
    }
}

/**
 * How the arranged library becomes rows.
 *
 * A reader scans series, not issues. Sixty series of twenty issues is twelve hundred cells,
 * and that is what the library drew before this: `LibrarySections` divided them into sixty
 * headings, which is a wall with signposts on it rather than a shelf. Kavita's own client
 * lists series and opens one to reach its issues, and the owner asked for that shape after
 * meeting the other on a phone.
 *
 * **A series takes the position of its first member and absorbs the rest.** That is the one
 * decision worth arguing about: gathering every member from across the shelf would undo the
 * sort the reader chose, which is the failure [LibrarySections] exists to avoid, and leaving
 * scattered members as separate rows would list one series twice. Taking the first
 * appearance keeps the arrangement's own answer about where the series belongs -- a shelf
 * sorted by last-read puts the series where its most recent issue put it -- and still yields
 * exactly one row per series.
 *
 * Pure and free of Compose, as [LibrarySections] is and for the same reason: the rule is
 * worth asserting directly rather than through a screenshot.
 */
internal object LibraryRows {

    /**
     * The arranged list as rows, in the arrangement's own order.
     *
     * A series of one is [LibraryRow.One], not a series with a single member: a row that
     * opens a list holding one thing is a tap the reader did not need to make.
     */
    fun of(publications: List<Publication>): List<LibraryRow> {
        val bySeries = publications
            .filter { !it.series.isNullOrBlank() }
            .groupBy { it.series!! }
        val taken = mutableSetOf<String>()
        val rows = mutableListOf<LibraryRow>()
        for (publication in publications) {
            val series = publication.series?.takeIf { it.isNotBlank() }
            val members = series?.let { bySeries[it] }
            when {
                series == null || members == null || members.size == 1 ->
                    rows += LibraryRow.One(publication)
                series in taken -> Unit
                else -> {
                    taken += series
                    rows += LibraryRow.Series(series, members)
                }
            }
        }
        return rows
    }
}

/**
 * What the shelf draws and which of its cells stand for a series.
 *
 * One value rather than three `remember`s at the call site: `LibraryScreen` is at its line
 * cap, and this is one decision -- how the arranged list becomes cells -- not three.
 */
internal data class ShelfRows(
    /** One publication per cell: itself, or the one standing for its series. */
    val shelved: List<Publication>,
    /** The cells that are a series, by the id of the publication standing for them. */
    val series: Map<String, LibraryRow.Series>,
)

/**
 * The arranged list as cells.
 *
 * Not while a search is running or a selection is open: results are already grouped by why
 * they matched, and a cell that opened a list mid-selection would throw away what the
 * reader had picked. In both cases the shelf lists publications, as it always did.
 */
@androidx.compose.runtime.Composable
internal fun rememberShelfRows(
    publications: List<Publication>,
    isGrouped: Boolean,
    isPicking: Boolean,
): ShelfRows = androidx.compose.runtime.remember(publications, isGrouped, isPicking) {
    if (isGrouped || isPicking) {
        ShelfRows(publications, emptyMap())
    } else {
        val rows = LibraryRows.of(publications)
        ShelfRows(
            shelved = rows.map { it.lead },
            series = rows.filterIsInstance<LibraryRow.Series>().associateBy { it.lead.id },
        )
    }
}
