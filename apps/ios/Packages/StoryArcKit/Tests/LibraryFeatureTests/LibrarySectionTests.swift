import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// How a long shelf divides, and — as much — when it refuses to.
///
/// `library-browsing`: a library "more than a reader can scan" is "divided by series where a
/// publication declares one, and otherwise by the active sort key", and "the sections follow
/// the sort rather than replacing it". That last clause is the one worth a suite: a grouping
/// that gathered every "A" from across a shelf would silently undo the order the reader
/// chose, and a screenshot of a phone showing four rows would never reveal it.
@Suite("Library sections")
struct LibrarySectionTests {

    private func publication(
        _ title: String,
        series: String? = nil,
        year: Int? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            year: year,
            origin: .inferred
        )
    }

    private func titles(_ sections: [LibrarySection]) -> [[String]] {
        sections.map { $0.publications.map(\.displayTitle) }
    }

    @Test("A series the shelf holds more than one of becomes a heading")
    func sharedSeriesBecomesASection() {
        let shelf = [
            publication("Saga #1", series: "Saga"),
            publication("Saga #2", series: "Saga"),
            publication("Zoo", series: nil)
        ]

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.map(\.title) == ["Saga", "Z"])
        #expect(titles(sections) == [["Saga #1", "Saga #2"], ["Zoo"]])
    }

    @Test("A series with one publication in it does not earn a heading of its own")
    func loneSeriesFallsBackToTheSortKey() {
        // Three hundred one-shots that each name a series would otherwise become three
        // hundred headings over one cover each, which is less structure than the wall of
        // covers it replaced, not more.
        let shelf = [
            publication("Akira", series: "Akira"),
            publication("Appleseed", series: "Appleseed")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        // One run, so nothing at all: a single heading over the whole shelf says nothing the
        // shelf did not already say.
        #expect(sections.isEmpty)
    }

    @Test("Sections are contiguous runs, so the sort survives them")
    func sectionsNeverReorderTheShelf() {
        // "A" appears twice, in two places. Two sections, not one gathered section — the
        // list stays in exactly the order it arrived in.
        let shelf = [
            publication("Akira"),
            publication("Berserk"),
            publication("Astro Boy")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["A", "B", "A"])
        #expect(sections.flatMap { $0.publications.map(\.displayTitle) }
            == shelf.map(\.displayTitle))
    }

    @Test("Every section has its own identity even when two share a heading")
    func repeatedHeadingsAreDistinctSections() {
        let shelf = [publication("Akira"), publication("Berserk"), publication("Astro Boy")]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(Set(sections.map(\.id)).count == sections.count)
    }

    @Test("A title that starts with no letter files under a symbol rather than under itself")
    func nonLetterTitlesShareOneHeading() {
        let shelf = [publication("13 Ghosts"), publication("300"), publication("Akira")]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["#", "A"])
        #expect(titles(sections) == [["13 Ghosts", "300"], ["Akira"]])
    }

    @Test("A year sort divides by year, and an unknown year is not filed as an early one")
    func yearSortDividesByYear() {
        let shelf = [
            publication("Watchmen", year: 1986),
            publication("Maus", year: 1986),
            publication("Unknown", year: nil)
        ]

        let sections = LibrarySections.divide(shelf, by: .year)

        #expect(sections.count == 2)
        #expect(sections[0].title == "1986")
        #expect(titles(sections) == [["Watchmen", "Maus"], ["Unknown"]])
    }

    @Test("A sort with no natural divisions leaves the shelf as one run")
    func continuousSortsAreNotDivided() {
        // Where the boundary between "recently" and "a while ago" falls is a decision no
        // file carries, and a heading that invented one would be the app asserting something
        // it does not know.
        let shelf = [publication("Akira"), publication("Berserk"), publication("Chew")]

        for sort in [LibrarySort.lastRead, .progress, .dateAdded, .fileSize] {
            #expect(LibrarySections.divide(shelf, by: sort).isEmpty)
        }
    }

    @Test("A shelf that divides into one section is not divided at all")
    func oneSectionIsNoSection() {
        let shelf = [publication("Akira"), publication("Astro Boy")]

        #expect(LibrarySections.divide(shelf, by: .title).isEmpty)
    }

    @Test("An empty shelf divides into nothing rather than into an empty heading")
    func emptyShelfHasNoSections() {
        #expect(LibrarySections.divide([], by: .title).isEmpty)
    }

    @Test("Dividing keeps every publication exactly once")
    func nothingIsLostOrDuplicated() {
        // The one property that makes the whole thing safe: a shelf with headings holds the
        // same books as the shelf without them.
        let shelf = [
            publication("Saga #1", series: "Saga"),
            publication("Saga #2", series: "Saga"),
            publication("Akira"),
            publication("Berserk"),
            publication("Saga #3", series: "Saga")
        ]

        let divided = LibrarySections.divide(shelf, by: .title)
            .flatMap(\.publications)
            .map(\.displayTitle)

        #expect(divided == shelf.map(\.displayTitle))
    }

    @Test("A series named only by whitespace is not a series")
    func blankSeriesIsIgnored() {
        let shelf = [
            publication("Akira", series: "  "),
            publication("Astro Boy", series: "  "),
            publication("Berserk")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["A", "B"])
    }
}
