import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// `publication-detail`, *Other issues in this series*: the rest of the series as a shelf,
/// in volume and chapter order, each marked read or not and on this Mac or not.
@Suite("Other issues in this series")
struct OtherIssuesTests {
    private func issue(_ id: String, series: String?, number: String? = nil, volume: Int? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(id).cbz"), format: .cbz,
            displayTitle: id, series: series, number: number, volume: volume, origin: .inferred
        )
    }

    @Test("The rest of the series, by volume then by the number as a person reads it, never itself")
    func order() {
        let open = issue("saga-2", series: "Saga", number: "2")
        let library = [
            issue("saga-10", series: "Saga", number: "10"), open,
            issue("saga-annual", series: "Saga"),
            issue("saga-3.5", series: "Saga ", number: "3.5"),
            issue("saga-1", series: "Saga", number: "1"),
            issue("saga-v2-1", series: "Saga", number: "1", volume: 2),
            issue("other", series: "Paper Girls", number: "1"),
        ]
        let rest = OtherIssues.rest(of: open, in: library).map(\.displayTitle)
        #expect(rest == ["saga-v2-1", "saga-1", "saga-3.5", "saga-10", "saga-annual"])
    }

    @Test("A publication with no series, or a blank one, has no shelf")
    func noSeries() {
        let library = [issue("a", series: nil), issue("b", series: "  "), issue("c", series: "  ")]
        #expect(OtherIssues.rest(of: library[0], in: library).isEmpty)
        #expect(OtherIssues.rest(of: library[1], in: library).isEmpty)
    }

    @Test("Each entry says whether it was read and whether it is on this Mac, in words too")
    func marks() {
        let entry = issue("saga-1", series: "Saga", number: "1")
        let read = OtherIssues.Entry(publication: entry, isRead: true, isOnThisMac: true)
        let away = OtherIssues.Entry(publication: entry, isRead: false, isOnThisMac: false)
        #expect(read.label == "#1")
        #expect(read.spoken.contains(String(localized: "desktop.detail.series.read")))
        #expect(away.spoken.contains(String(localized: "desktop.detail.series.notHere")))
        #expect(!away.spoken.contains(String(localized: "desktop.detail.series.read")))
    }
}
