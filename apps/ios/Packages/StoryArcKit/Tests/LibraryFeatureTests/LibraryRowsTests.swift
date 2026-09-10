import StoryArcCore
import Testing

@testable import LibraryFeature

/// What the library lists when its publications belong to series.
///
/// `library-browsing`: a series "is listed once, as a single cell", its issues "are not
/// listed beside it, whatever source they came from", and a publication with no series "is a
/// row of its own". Android's `LibraryRowsTest` answers the same seven cases.
struct LibraryRowsTests {

    private func issue(_ title: String, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            origin: .embedded
        )
    }

    @Test("A series is one row, however many issues it holds")
    func oneRowPerSeries() {
        let rows = LibraryRows.of([
            issue("a", series: "Lantern"), issue("b", series: "Lantern"), issue("c", series: "Lantern"),
        ])

        #expect(rows.count == 1)
        #expect(rows[0].count == 3)
    }

    @Test("A publication with no series is a row of its own")
    func standalone() {
        let rows = LibraryRows.of([issue("standalone")])

        #expect(rows.count == 1)
        #expect(rows[0].count == nil)
        #expect(rows[0].lead.displayTitle == "standalone")
    }

    @Test("A series of one is not a series a reader has to open")
    func seriesOfOne() {
        let rows = LibraryRows.of([issue("only", series: "Lantern")])

        #expect(rows[0].count == nil)
    }

    @Test("A series takes the place its first member had")
    func firstAppearanceWins() {
        let rows = LibraryRows.of([
            issue("solo"),
            issue("a", series: "Lantern"),
            issue("later"),
            issue("b", series: "Lantern"),
        ])

        #expect(rows.map(\.lead.displayTitle) == ["solo", "a", "later"])
        #expect(rows[1].count == 2)
    }

    @Test("A scattered series is still one row and keeps every member")
    func scattered() {
        let rows = LibraryRows.of([
            issue("a", series: "Lantern"), issue("x", series: "Titans"), issue("b", series: "Lantern"),
        ])

        #expect(rows.count == 2)
        guard case let .series(_, members) = rows[0] else {
            Issue.record("the first row should be the Lantern series")
            return
        }
        #expect(members.map(\.displayTitle) == ["a", "b"])
    }

    @Test("A blank series name is no series at all")
    func blankSeries() {
        let rows = LibraryRows.of([issue("a", series: ""), issue("b", series: " ")])

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count == nil })
    }

    @Test("An empty library has no rows")
    func empty() {
        #expect(LibraryRows.of([]).isEmpty)
    }
}
