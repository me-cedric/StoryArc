internal import Foundation

public import Persistence
public import StoryArcCore

/// Setting a status by hand, for a series whose source reports none.
///
/// `library-browsing` (D36): the reported half of a status is carried onto ``Publication``
/// itself at index time; this is the other half, read fresh from ``SeriesStatusStore`` rather
/// than held on ``LibraryModel``, so adding it cost that file not one stored property — it
/// sits exactly at the 400-line cap `.swiftlint.yml` enforces as an error under `--strict`,
/// and a constructor-injected store would have added an `init` parameter, a stored property
/// and an assignment, none of which fit. A test that needs an isolated store passes one of
/// its own to any function here; every one of them defaults to `SeriesStatusStore()`, the
/// same default the store's own initialiser gives for production. Android's
/// `SeriesStatusActions.kt` mirrors this file, for the matching reason given there:
/// `LibraryViewModel.kt` is a recorded ratchet file and must not grow either.
extension LibraryModel {
    /// Every status a reader has set by hand, keyed by series name.
    func seriesStatusOverrides(store: SeriesStatusStore = SeriesStatusStore()) -> [String: PublicationStatus] {
        store.all()
    }

    /// The statuses actually present in the library, reported or set by hand, in
    /// ``PublicationStatus``'s own declared order.
    ///
    /// `library-browsing`: the filter menu "never offers a value that would empty the
    /// shelf", the rule every other facet in `LibraryFacets.swift` already follows.
    public func availableStatuses(store: SeriesStatusStore = SeriesStatusStore()) -> [PublicationStatus] {
        let shown = withManualStatuses(publications, overrides: seriesStatusOverrides(store: store))
        let present = Set(shown.compactMap(\.status))
        return PublicationStatus.allCases.filter(present.contains)
    }

    /// Whether any member of a series already carries a status its own source reported.
    ///
    /// D36: "a status a source reports is not editable by the reader — only a series with
    /// no reported status takes one set by hand". Read from ``publications`` rather than the
    /// overlaid list: the question is whether a *source* has said something, and the overlay
    /// exists precisely to answer that question the other way round.
    public func seriesHasReportedStatus(_ series: String) -> Bool {
        publications.contains { $0.series == series && $0.status != nil }
    }

    /// Sets, or replaces, the status a reader chose for a series with no reported one.
    public func setSeriesStatus(
        _ status: PublicationStatus,
        for series: String,
        store: SeriesStatusStore = SeriesStatusStore()
    ) {
        store.set(status, for: series)
        rebuild()
    }

    /// Clears a status the reader had set, leaving the series unset again.
    public func clearSeriesStatus(_ series: String, store: SeriesStatusStore = SeriesStatusStore()) {
        store.clear(series)
        rebuild()
    }
}
