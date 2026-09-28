package app.storyarc.feature.library

import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope

/**
 * Everything that is narrowing the shelf, counted once and cleared once.
 *
 * `library-browsing`, *Combining filters*: the filters "combine with AND, the active count is
 * visible on the filter control, and a single action clears them all". A count and a clear
 * that disagree is the defect this value exists to make impossible -- a chip reading "2
 * filters active" that puts three things back is a chip nobody trusts twice.
 *
 * Three narrowings, not one. [LibraryQuery.activeFilterCount] counts the seven facets the
 * query holds and cannot count the other two, because the download group and the availability
 * axis are fields beside the query rather than in it.
 *
 * **Availability is cleared and not counted, and that asymmetry is deliberate.** The axis has
 * a control of its own that always states which side it is on, so a reader can see it without
 * opening the filter menu; the badge speaks for what is hidden inside the menu. Clearing still
 * puts it back, because *Filter persistence* forbids leaving a reader with an empty-looking
 * shelf and a button that does not empty it.
 *
 * A value beside the view rather than a rule inside it, so the same answer reaches the chip's
 * badge, both clear actions and a test. iOS's `LibraryNarrowing` is its twin.
 */
internal data class LibraryNarrowing(
    val query: LibraryQuery,
    val downloads: DownloadFilter = DownloadFilter.EITHER,
    val availability: LibraryAvailability = LibraryAvailability.EVERYTHING,
) {
    /** Whether the shelf is narrowed to one library. */
    val isScoped: Boolean get() = query.scope != LibraryScope.AllSources

    /** How many groups the badge speaks for. */
    val activeCount: Int
        get() = query.activeFilterCount +
            (if (isScoped) 1 else 0) +
            (if (downloads.isActive) 1 else 0)

    val isActive: Boolean get() = activeCount > 0

    /**
     * Every narrowing undone.
     *
     * @param includingSearch also drops the term. The empty state's button undoes the search
     *   as well, because a reader who searched and found nothing is looking at a shelf the
     *   term emptied; the filter menu's own action keeps it, because the reader can see the
     *   field and did not ask for it to be cleared.
     */
    fun cleared(includingSearch: Boolean = false): LibraryNarrowing = copy(
        query = query.withoutFilters()
            .copy(
                scope = LibraryScope.AllSources,
                search = if (includingSearch) "" else query.search,
            ),
        downloads = DownloadFilter.EITHER,
        availability = LibraryAvailability.EVERYTHING,
    )
}
