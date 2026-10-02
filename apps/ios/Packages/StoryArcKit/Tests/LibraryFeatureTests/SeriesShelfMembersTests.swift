import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// `library-browsing`: "when a reader opens a series, then its publications are listed in
/// their own order" -- the library's `SERIES` comparison (number, then natural filename), not
/// the order the library adopted them in.
///
/// Android's `SeriesShelfMembersTest` asserts the same cases.
@Suite("Series shelf ordering")
struct SeriesShelfMembersTests {

    private func publication(_ title: String, series: String, number: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            number: number,
            origin: .inferred
        )
    }

    @Test("A series opened out of adoption order is listed by issue number")
    func sortedByIssueNumber() {
        let library = [
            publication("Issue 10", series: "Nightjar", number: "10"),
            publication("Issue 2", series: "Nightjar", number: "2"),
            publication("Issue 1", series: "Nightjar", number: "1"),
        ]
        let members = seriesShelfMembers(named: "Nightjar", in: library)
        #expect(members.map(\.displayTitle) == ["Issue 1", "Issue 2", "Issue 10"])
    }

    @Test("Only that series' own members are listed")
    func onlyThatSeries() {
        let library = [
            publication("Nightjar #1", series: "Nightjar", number: "1"),
            publication("Ashfall #1", series: "Ashfall", number: "1"),
        ]
        let members = seriesShelfMembers(named: "Nightjar", in: library)
        #expect(members.map(\.displayTitle) == ["Nightjar #1"])
    }
}
