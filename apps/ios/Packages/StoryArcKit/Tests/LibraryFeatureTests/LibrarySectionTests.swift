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
///
/// The refusals matter as much as the divisions. A shelf of unrelated files with a distinct
/// initial each divides into a tall column of near-empty rows, every one of them announced —
/// worse to read than the wall of covers the requirement was written to fix. That was found
/// on a booted simulator, not in this file, and it is asserted here so it cannot come back.
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

    /// A run of one series, long enough that no heading in these shelves is a stray.
    private func series(_ name: String, _ count: Int) -> [Publication] {
        (1...count).map { publication("\(name) #\($0)", series: name) }
    }

    private func titles(_ sections: [LibrarySection]) -> [[String]] {
        sections.map { $0.publications.map(\.displayTitle) }
    }

    @Test("A series the shelf holds more than one of becomes a heading")
    func sharedSeriesBecomesASection() {
        let shelf = series("Ashfall", 4) + series("Blackwater", 4)

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.map(\.title) == ["Ashfall", "Blackwater"])
        #expect(titles(sections).map(\.count) == [4, 4])
    }

    @Test("A series with one publication in it does not earn a heading of its own")
    func loneSeriesFallsBackToTheSortKey() {
        // Three hundred one-shots that each name a series would otherwise become three
        // hundred headings over one cover each, which is less structure than the wall of
        // covers it replaced, not more.
        let shelf = [
            publication("Akira", series: "Akira"),
            publication("Appleseed", series: "Appleseed"),
            publication("Astro Boy", series: "Astro Boy"),
            publication("Berserk", series: "Berserk"),
            publication("Blame", series: "Blame"),
            publication("Blacksad", series: "Blacksad")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["A", "B"])
        #expect(titles(sections).map(\.count) == [3, 3])
    }

    @Test("A shelf whose standalones fall either side of a series is not divided")
    func repeatedHeadingsRefuseTheDivision() {
        // This shelf draws *Other*, then *Ashfall*, then *Other* again, and a reader reads
        // the second one as a different pile. Seen on a booted simulator: one stray file
        // sorting before the first series was enough to produce it.
        //
        // `LibraryIndex.compare(by: .series)` no longer *hands* the shelf over in this order
        // — a publication with no series now sorts after every publication that has one, and
        // `mixedLibraryDividesOnceStandalonesSortLast` below is the same books arranged by
        // that rule. The order is written out by hand here because the refusal is the
        // backstop: `divide` is given a list, and a list that would repeat a heading has to
        // be refused whatever produced it.
        let shelf = [publication("archive-comment")]
            + series("Ashfall", 6)
            + [publication("truncated"), publication("zip64"), publication("tar-store")]

        #expect(LibrarySections.divide(shelf, by: .series).isEmpty)
    }

    @Test("A library of series and standalones, arranged by series, divides into two runs")
    func mixedLibraryDividesOnceStandalonesSortLast() {
        // The point of sorting a publication with no series after every publication that has
        // one. These are the exact books the refusal above is written over; arranged rather
        // than hand-ordered, the standalones form one contiguous pile at the end and the
        // shelf divides cleanly instead of declining to divide at all.
        let shelf = LibraryIndex.arrange(
            [publication("archive-comment")]
                + series("Ashfall", 6)
                + [publication("truncated"), publication("zip64"), publication("tar-store")],
            query: LibraryQuery(sort: .series),
            locale: Locale(identifier: "en_US")
        )

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.count == 2)
        #expect(sections[0].title == "Ashfall")
        #expect(sections[0].publications.count == 6)
        // The standalone pile, whole and in one place. Its heading is a localized word
        // rather than data off a file, so what is asserted is that it holds all four and
        // that no heading is drawn twice.
        #expect(titles(sections)[1] == ["archive-comment", "tar-store", "truncated", "zip64"])
        #expect(Set(sections.map(\.title)).count == sections.count)
    }

    @Test("Sections are contiguous runs, so the sort survives them")
    func sectionsNeverReorderTheShelf() {
        // The shelf arrives in the order `LibraryIndex.arrange` left it in, and dividing it
        // never moves a publication.
        let shelf = series("Ashfall", 4) + series("Blackwater", 4) + series("Cinderfall", 4)

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.flatMap { $0.publications.map(\.displayTitle) }
            == shelf.map(\.displayTitle))
    }

    @Test("Every section has its own identity, so two sharing a heading are two places")
    func sectionsAreDistinct() {
        let shelf = series("Ashfall", 4) + series("Blackwater", 4)

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(Set(sections.map(\.id)).count == sections.count)
    }

    @Test("A title that starts with no letter files under a symbol rather than under itself")
    func nonLetterTitlesShareOneHeading() {
        let shelf = [
            publication("13 Ghosts"),
            publication("300"),
            publication("2000 AD"),
            publication("Akira"),
            publication("Astro Boy"),
            publication("Appleseed")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["#", "A"])
        #expect(titles(sections).map(\.count) == [3, 3])
    }

    @Test("A year sort divides by year, and an unknown year is not filed as an early one")
    func yearSortDividesByYear() {
        let shelf = [
            publication("Watchmen", year: 1986),
            publication("Maus", year: 1986),
            publication("Dark Knight", year: 1986),
            publication("Unknown A"),
            publication("Unknown B"),
            publication("Unknown C")
        ]

        let sections = LibrarySections.divide(shelf, by: .year)

        #expect(sections.map(\.title).first == "1986")
        #expect(sections.count == 2)
        #expect(titles(sections).map(\.count) == [3, 3])
    }

    @Test("Under a series sort, everything with no series shares one heading")
    func seriesSortGathersTheStandalones() {
        // Filing them under their initials would answer a question the reader did not ask,
        // and would scatter the standalone half of a library across twenty headings that all
        // mean "no series".
        let shelf = series("Ashfall", 4) + [
            publication("Akira"),
            publication("Berserk"),
            publication("Chew"),
            publication("Daytripper")
        ]

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.count == 2)
        #expect(sections[0].title == "Ashfall")
        #expect(sections[1].publications.count == 4)
    }

    @Test("A sort with no natural divisions leaves an unserialised shelf as one run")
    func continuousSortsAreNotDivided() {
        // Where the boundary between "recently" and "a while ago" falls is a decision no
        // file carries, and a heading that invented one would be the app asserting something
        // it does not know. A series still earns its heading under these sorts — the
        // requirement puts series first — so this shelf deliberately declares none.
        let shelf = [
            publication("Akira"),
            publication("Berserk"),
            publication("Chew"),
            publication("Daytripper")
        ]

        for sort in [LibrarySort.lastRead, .progress, .dateAdded, .fileSize] {
            #expect(LibrarySections.divide(shelf, by: sort).isEmpty)
        }
    }

    @Test("A series stays a heading under a sort that divides into nothing else")
    func seriesSurvivesAContinuousSort() {
        // "Divided by series where a publication declares one, and otherwise by the active
        // sort key" — series first, whatever the sort. The scatter rule is what stops that
        // from producing the same heading twice.
        let shelf = series("Ashfall", 4) + series("Blackwater", 4)

        #expect(LibrarySections.divide(shelf, by: .lastRead).map(\.title)
            == ["Ashfall", "Blackwater"])
    }

    @Test("A shelf that divides into one section is not divided at all")
    func oneSectionIsNoSection() {
        #expect(LibrarySections.divide(series("Ashfall", 8), by: .series).isEmpty)
    }

    @Test("A division that does not average a row of covers a heading is refused")
    func sparseDivisionsAreRefused() {
        // Twenty-two unrelated files with a distinct initial each. Sectioning turns one
        // dense grid into a tall column of near-empty rows, every one announced — worse to
        // read than the wall it replaced. Seen on a booted simulator with the test corpus,
        // which is exactly this shelf.
        let letters = "ABCDEFGHIJKLMNOPQRSTUV"
        let shelf = letters.map { publication("\($0)ne of a kind") }

        #expect(shelf.count == 22)
        #expect(LibrarySections.divide(shelf, by: .title).isEmpty)
    }

    @Test("The same shelf divides once its headings each cover a row and more")
    func denseDivisionsAreKept() {
        let shelf = series("Ashfall", 6) + series("Blackwater", 6) + series("Cinderfall", 6)

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.map(\.title) == ["Ashfall", "Blackwater", "Cinderfall"])
    }

    @Test("An empty shelf divides into nothing rather than into an empty heading")
    func emptyShelfHasNoSections() {
        #expect(LibrarySections.divide([], by: .title).isEmpty)
    }

    @Test("Dividing keeps every publication exactly once")
    func nothingIsLostOrDuplicated() {
        // The one property that makes the whole thing safe: a shelf with headings holds the
        // same books as the shelf without them.
        let shelf = series("Ashfall", 5)
            + [publication("Akira"), publication("Astro Boy"), publication("Blame")]
            + series("Blackwater", 5)

        let divided = LibrarySections.divide(shelf, by: .series)
            .flatMap(\.publications)
            .map(\.displayTitle)

        #expect(divided == shelf.map(\.displayTitle))
    }

    @Test("A series the sort scatters is not a heading, because two of them are two places")
    func scatteredSeriesIsDemoted() {
        // Sorted by title, "Ashfall #3" is filed under T and "Ashfall #4" under W, with
        // other books between them. Two sections headed "Ashfall" would read as the app
        // having lost half a series, so both fall back to the letter the sort filed them
        // under.
        let shelf = [
            publication("The Long Count", series: "Ashfall"),
            publication("The Third Chapter"),
            publication("The Quiet Season"),
            publication("Undeclared Direction"),
            publication("Unsupported Codec"),
            publication("Undertow"),
            publication("What the Courier Carried", series: "Ashfall"),
            publication("What Came After"),
            publication("Whiteout")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["T", "U", "W"])
    }

    @Test("A series the sort keeps together is still a heading")
    func contiguousSeriesSurvivesTheDemotion() {
        // The same publications, sorted by series: now they are adjacent, one heading covers
        // both, and the demotion above must not fire.
        let shelf = series("Ashfall", 4) + [
            publication("Undeclared Direction"),
            publication("Unsupported Codec"),
            publication("Undertow"),
            publication("Whiteout")
        ]

        let sections = LibrarySections.divide(shelf, by: .series)

        #expect(sections.map(\.title).first == "Ashfall")
        #expect(sections.count == 2)
    }

    @Test("A series named only by whitespace is not a series")
    func blankSeriesIsIgnored() {
        let shelf = [
            publication("Akira", series: "  "),
            publication("Astro Boy", series: "  "),
            publication("Appleseed", series: "  "),
            publication("Berserk"),
            publication("Blame"),
            publication("Blacksad")
        ]

        let sections = LibrarySections.divide(shelf, by: .title)

        #expect(sections.map(\.title) == ["A", "B"])
    }
}
