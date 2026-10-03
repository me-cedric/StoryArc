import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// Setting a status by hand, for a series whose source reports none.
///
/// Asserted against the same table as Android's `SeriesStatusActionsTest`.
@MainActor
struct SeriesStatusActionsTests {
    private func publication(
        _ title: String,
        series: String?,
        status: PublicationStatus? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            status: status,
            origin: .inferred
        )
    }

    private func store() throws -> SeriesStatusStore {
        let defaults = try #require(UserDefaults(suiteName: "series-status-actions-\(UUID().uuidString)"))
        return SeriesStatusStore(defaults: defaults)
    }

    @Test("A reader-set status is offered among the available ones")
    func readerSetStatusIsAvailable() throws {
        let model = LibraryModel()
        model.publications = [publication("Tidal Reach #1", series: "Tidal Reach")]
        let store = try store()
        model.setSeriesStatus(.completed, for: "Tidal Reach", store: store)
        #expect(model.availableStatuses(store: store) == [.completed])
    }

    @Test("A series with a reported status is not hand-editable")
    func reportedSeriesIsNotHandEditable() {
        let model = LibraryModel()
        model.publications = [publication("Saga #1", series: "Saga", status: .ongoing)]
        #expect(model.seriesHasReportedStatus("Saga"))
    }

    @Test("A series with no reported status is hand-editable")
    func unreportedSeriesIsHandEditable() {
        let model = LibraryModel()
        model.publications = [publication("Maus #1", series: "Maus")]
        #expect(!model.seriesHasReportedStatus("Maus"))
    }

    @Test("Setting a status by hand reaches what the shelf actually filters to")
    func handSetStatusReachesTheShelf() throws {
        // `rebuild()` cannot take a store of its own — see this file's own doc comment on
        // why `LibraryModel` holds no stored property for one — so it always reads the
        // default `SeriesStatusStore()`. Proving the override actually reaches `visible`
        // means going through that same default, with the one series this test touches
        // cleared afterward.
        defer { SeriesStatusStore().clear("Tidal Reach") }
        let model = LibraryModel()
        model.publications = [
            publication("Tidal Reach #1", series: "Tidal Reach"),
            publication("Maus #1", series: "Maus"),
        ]
        model.setSeriesStatus(.completed, for: "Tidal Reach")
        model.query.statuses = [.completed]
        #expect(model.visible.map(\.displayTitle) == ["Tidal Reach #1"])
    }

    @Test("Clearing a hand-set status removes it from what is available")
    func clearingRemovesIt() throws {
        let model = LibraryModel()
        model.publications = [publication("Maus #1", series: "Maus")]
        let store = try store()
        model.setSeriesStatus(.completed, for: "Maus", store: store)
        model.clearSeriesStatus("Maus", store: store)
        #expect(model.availableStatuses(store: store).isEmpty)
    }
}
