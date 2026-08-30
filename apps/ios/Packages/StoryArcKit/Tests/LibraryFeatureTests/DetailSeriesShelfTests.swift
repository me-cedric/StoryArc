import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The rest of the series, in the order a person reads it.
///
/// `publication-detail` asks for the shelf "in volume and chapter order", and issue numbers
/// are strings because "3.5" and "Annual 1" are both real. A plain string sort puts 10
/// before 2 and puts an unnumbered annual at the head of the run — both of which look like
/// data problems rather than a sort, which is why the order is asserted rather than eyeballed.
@Suite("Series shelf order")
struct DetailSeriesShelfTests {

    private func issue(
        _ title: String,
        series: String? = "Bone",
        number: String? = nil,
        volume: Int? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            series: series,
            number: number,
            volume: volume,
            origin: .inferred
        )
    }

    @Test("Numbers sort the way they are read, not the way they are spelled")
    func naturalNumberOrder() {
        let library = [
            issue("Bone 10", number: "10"),
            issue("Bone 2", number: "2"),
            issue("Bone 3.5", number: "3.5"),
            issue("Bone 3", number: "3"),
        ]

        let rest = DetailSeriesShelf.rest(of: library[1], in: library)

        #expect(rest.map(\.number) == ["3", "3.5", "10"])
    }

    @Test("Volume comes before number")
    func volumeLeads() {
        let library = [
            issue("Two/1", number: "1", volume: 2),
            issue("One/9", number: "9", volume: 1),
            issue("One/1", number: "1", volume: 1),
        ]

        let rest = DetailSeriesShelf.rest(of: library[1], in: library)

        #expect(rest.map(\.displayTitle) == ["One/1", "Two/1"])
    }

    /// An annual with no issue number belongs after the run, not before issue one.
    @Test("An unnumbered publication sorts last")
    func unnumberedSortsLast() {
        let library = [
            issue("Bone Annual"),
            issue("Bone 1", number: "1"),
            issue("Bone 2", number: "2"),
        ]

        let rest = DetailSeriesShelf.rest(of: library[1], in: library)

        #expect(rest.map(\.displayTitle) == ["Bone 2", "Bone Annual"])
    }

    @Test("The publication the page is about is never on its own shelf")
    func excludesItself() {
        let library = [issue("Bone 1", number: "1"), issue("Bone 2", number: "2")]

        #expect(DetailSeriesShelf.rest(of: library[0], in: library).count == 1)
    }

    /// Absent rather than empty: the shelf is not drawn at all, so a heading over nothing
    /// never reaches the page.
    @Test("A publication with no series, or the only one of its series, has no shelf")
    func noShelfWhenThereIsNoSeries() {
        let alone = issue("One-shot", series: nil)
        #expect(DetailSeriesShelf.rest(of: alone, in: [alone]).isEmpty)

        let only = issue("Bone 1", number: "1")
        #expect(DetailSeriesShelf.rest(of: only, in: [only]).isEmpty)
    }

    @Test("Another series is not this series")
    func otherSeriesAreExcluded() {
        let library = [
            issue("Bone 1", number: "1"),
            issue("Akira 1", series: "Akira", number: "1"),
        ]

        #expect(DetailSeriesShelf.rest(of: library[0], in: library).isEmpty)
    }
}
