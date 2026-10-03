package app.storyarc.feature.library

import android.app.Application
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationStatus
import app.storyarc.core.model.withManualStatuses
import app.storyarc.core.persistence.SeriesStatusStore

/**
 * Setting a status by hand, for a series whose source reports none.
 *
 * `library-browsing` (D36): the reported half of a status is carried onto [Publication]
 * itself at index time; this is the other half, read fresh from [SeriesStatusStore] rather
 * than held on [LibraryViewModel] -- which is a recorded ratchet file (`scripts/line-cap.mjs`)
 * at exactly its recorded length, and a constructor-injected store would have added a
 * parameter, a field and an assignment line, none of which fit. iOS's
 * `SeriesStatusActions.swift` mirrors this file, for the matching reason given there:
 * `LibraryModel.swift` sits at the 400-line SwiftLint cap enforced as an error under
 * `pnpm lint`'s `--strict`.
 */
private fun LibraryViewModel.seriesStatusStore(): SeriesStatusStore =
    SeriesStatusStore.open(getApplication<Application>())

/** Every status a reader has set by hand, keyed by series name. */
internal fun LibraryViewModel.withSeriesStatuses(publications: List<Publication>): List<Publication> =
    withManualStatuses(publications, seriesStatusStore().all())

/** The status a reader set by hand for one series, or null where they have set none. */
fun LibraryViewModel.manualStatus(series: String): PublicationStatus? = seriesStatusStore().all()[series]

/**
 * The statuses actually present in the library, reported or set by hand, in
 * [PublicationStatus]'s own declared order.
 *
 * `library-browsing`: the filter menu "never offers a value that would empty the shelf", the
 * rule every other facet in `LibraryFacets.kt` already follows.
 */
fun LibraryViewModel.availableStatuses(): List<PublicationStatus> {
    val present = withSeriesStatuses(publications.value).mapNotNull { it.status }.toSet()
    return PublicationStatus.entries.filter { it in present }
}

/**
 * Whether any member of a series already carries a status its own source reported.
 *
 * D36: "a status a source reports is not editable by the reader -- only a series with no
 * reported status takes one set by hand". Read from [LibraryViewModel.publications] rather
 * than the overlaid list: the question is whether a *source* has said something, and the
 * overlay exists precisely to answer that question the other way round.
 */
fun LibraryViewModel.seriesHasReportedStatus(series: String): Boolean =
    publications.value.any { it.series == series && it.status != null }

/** Sets, or replaces, the status a reader chose for a series with no reported one. */
fun LibraryViewModel.setSeriesStatus(series: String, status: PublicationStatus) {
    seriesStatusStore().set(series, status)
    rebuild()
}

/** Clears a status the reader had set, leaving the series unset again. */
fun LibraryViewModel.clearSeriesStatus(series: String) {
    seriesStatusStore().clear(series)
    rebuild()
}
