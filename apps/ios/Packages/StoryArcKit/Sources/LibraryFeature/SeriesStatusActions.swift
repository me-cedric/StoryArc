internal import Foundation

public import Persistence
public import StoryArcCore

/// Setting a status by hand, for a series whose source reports none.
///
/// `library-browsing` (D36): the reported half of a status is carried onto ``Publication``
/// itself at index time; this is the other half. ``SeriesStatusStore`` persists it, and
/// ``LibraryModel/seriesStatuses`` holds the copy the screens observe, so the series menu and
/// the filter menu redraw when a status is set or cleared. `LibraryModel.swift` sits at the
/// 400-line cap `.swiftlint.yml` enforces as an error under `--strict`, which is why these
/// actions live here. A test that needs an isolated store passes one of its own; each action
/// defaults to `SeriesStatusStore()`, the store the model loads from at launch. Android's
/// `SeriesStatusActions.kt` mirrors this file.
extension LibraryModel {
    /// The statuses actually present in the library, reported or set by hand, in
    /// ``PublicationStatus``'s own declared order.
    ///
    /// `library-browsing`: the filter menu "never offers a value that would empty the
    /// shelf", the rule every other facet in `LibraryFacets.swift` already follows.
    public func availableStatuses() -> [PublicationStatus] {
        let shown = withManualStatuses(publications, overrides: seriesStatuses)
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
        seriesStatuses = store.all()
        rebuild()
    }

    /// Clears a status the reader had set, leaving the series unset again.
    public func clearSeriesStatus(_ series: String, store: SeriesStatusStore = SeriesStatusStore()) {
        store.clear(series)
        seriesStatuses = store.all()
        rebuild()
    }
}
