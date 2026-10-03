import Testing

@testable import StoryArcCore

/// Filling in a reader-set status for a series whose source reports none.
///
/// Asserted against the same table as Android's `SeriesStatusTest`.
struct SeriesStatusTests {
    private func publication(
        _ title: String,
        series: String?,
        status: PublicationStatus?
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

    @Test("A series with no reported status takes the one the reader set")
    func unreportedTakesManual() {
        let library = [publication("Watchmen #1", series: "Watchmen", status: nil)]
        let overlaid = withManualStatuses(library, overrides: ["Watchmen": .completed])
        #expect(overlaid[0].status == .completed)
    }

    @Test("A series with a reported status keeps it, whatever the reader set")
    func reportedSurvivesTheOverlay() {
        let library = [publication("Saga #1", series: "Saga", status: .ongoing)]
        let overlaid = withManualStatuses(library, overrides: ["Saga": .cancelled])
        #expect(overlaid[0].status == .ongoing)
    }

    @Test("A publication with no series is never given a status")
    func noSeriesNeverTakesOne() {
        let library = [publication("One-shot", series: nil, status: nil)]
        // The override is keyed by a series this one-shot does not have, so it is a mistake
        // to apply it even if a stray key happened to be empty and a series name matched it.
        let overlaid = withManualStatuses(library, overrides: ["": .ongoing])
        #expect(overlaid[0].status == nil)
    }

    @Test("A series with no override at all is left unset")
    func noOverrideLeavesItUnset() {
        let library = [publication("Maus #1", series: "Maus", status: nil)]
        let overlaid = withManualStatuses(library, overrides: [:])
        #expect(overlaid[0].status == nil)
    }
}
