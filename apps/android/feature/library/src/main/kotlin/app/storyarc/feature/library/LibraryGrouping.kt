package app.storyarc.feature.library

/**
 * Whether the shelf presents a series as one cell, or every issue as its own row.
 *
 * `library-browsing`'s *A series is one row* scenario describes the first, and its *A shelf
 * of issues* scenario describes the second. The library already holds one `Publication` per
 * issue and groups them for display, so this decides a presentation over data the app
 * already has — never a second fetch, and never a second store.
 *
 * **Two cases, not two more cases on `LibraryLayout`.** Grid-or-list and series-or-issues are
 * two axes, and one enum of four states would make the next layout question a multiple of
 * this one.
 *
 * Held beside the library's screens rather than on `LibraryQuery`, exactly as
 * [DownloadFilter] is and for the reason that type sets out: the query is the value both
 * platforms encode, and a case added to it is a change to `:core:model` and to iOS's mirror
 * of it. iOS keeps the same two answers in `LibraryGrouping.swift`.
 */
enum class LibraryGrouping {
    /**
     * A series is one cell, carrying its own artwork and how many publications it holds.
     *
     * First in the list and the default, because the owner reversed the first build to get
     * it: a library of sixty series of twenty issues is twelve hundred cells otherwise.
     */
    SERIES,

    /** Every publication is its own cell, the ones a series held included. */
    ISSUES,
    ;

    /**
     * Whether this answer collapses a series into one cell.
     *
     * The whole rule, in one place, so both platforms can assert it rather than read it off a
     * menu. [rememberShelfRows] asks it, and iOS's `LibraryView.rows` asks its twin.
     */
    val isCollapsing: Boolean get() = this == SERIES

    companion object {
        /**
         * The name `LibraryPreferences` wrote down, turned back into a choice.
         *
         * [SERIES] for anything it cannot read, for the reason [DownloadFilter.named] gives:
         * a reader who never chose must be given what they already see.
         */
        fun named(name: String?): LibraryGrouping =
            entries.firstOrNull { it.name == name } ?: SERIES
    }
}
