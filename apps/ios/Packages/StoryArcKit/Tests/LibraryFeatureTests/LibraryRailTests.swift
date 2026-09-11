import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which letters the index offers, and the five sorts under which it offers none.
///
/// `library-browsing`'s *An index down the side of a long shelf* and *A sort no letter
/// describes* scenarios are what these cases hold. Android's `LibraryRailTest` answers the
/// same ones.
struct LibraryRailTests {

    private func issue(_ title: String, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            origin: .embedded
        )
    }

    /// Thirteen publications, which is one more than ``LibrarySections/threshold``.
    private func thirteen(_ titles: [String]) -> [Publication] {
        #expect(titles.count > LibrarySections.threshold)
        return titles.map { issue($0) }
    }

    private let letters = [
        "Ashfall", "Blackwater", "Cinder", "Drift", "Ember", "Fathom", "Glass",
        "Harrow", "Ironwood", "Jubilee", "Kestrel", "Lantern", "Moth",
    ]

    @Test("A title sort offers one entry per letter the shelf files a row under")
    func titleSort() {
        let entries = LibraryRail.of(thirteen(letters), sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.map(\.label) == ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"])
        #expect(entries[0].publicationID == thirteen(letters)[0].id)
    }

    /// The sort key, not the raw title. `library-browsing` alphabetises a title with its
    /// leading article ignored, so a label read off the raw title would say T in the middle
    /// of the S run and the index would stop describing the shelf.
    @Test("The Sandman files under S")
    func articlesAreIgnored() {
        var titles = letters
        titles[0] = "The Sandman"
        let entries = LibraryRail.of(thirteen(titles), sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.first?.label == "S")
        #expect(!entries.map(\.label).contains("T"))
    }

    @Test("A title no letter claims is offered as #")
    func nonLetter() {
        var titles = letters
        titles[0] = "2000 AD"
        let entries = LibraryRail.of(thirteen(titles), sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.first?.label == "#")
    }

    @Test("Five sorts file nothing under a letter, and offer no index at all")
    func noIndexForContinuousSorts() {
        for sort in [LibrarySort.lastRead, .progress, .year, .dateAdded, .fileSize] {
            #expect(LibraryRail.of(thirteen(letters), sort: sort, locale: Locale(identifier: "en")).isEmpty)
        }
    }

    /// The whole of the hide-rather-than-disable decision: the caller draws nothing, so no
    /// reader meets a control that refuses every touch.
    @Test("A shelf short enough to scan offers no index")
    func shortShelf() {
        let short = Array(letters.prefix(LibrarySections.threshold)).map { issue($0) }

        #expect(short.count == LibrarySections.threshold)
        #expect(LibraryRail.of(short, sort: .title, locale: Locale(identifier: "en")).isEmpty)
    }

    @Test("One letter over the whole shelf is a label rather than an index")
    func oneLetter() {
        let all = (1...13).map { issue("Ashfall #\($0)") }

        #expect(LibraryRail.of(all, sort: .title, locale: Locale(identifier: "en")).isEmpty)
    }

    /// `LibraryIndex.compareBySeries` puts every series-less publication after every series,
    /// in one pile, so the `#` entry is one contiguous run at the end rather than a second
    /// alphabet run through the first.
    @Test("A series sort files a publication naming no series under #")
    func seriesSort() {
        var shelf = (1...10).map { issue("issue \($0)", series: "Lantern") }
        shelf += (1...3).map { issue("loose \($0)") }
        let entries = LibraryRail.of(shelf, sort: .series, locale: Locale(identifier: "en"))

        #expect(entries.map(\.label) == ["L", "#"])
        #expect(entries[1].publicationID == shelf[10].id)
    }

    @Test("A repeated letter is one entry, pointing at the first row under it")
    func distinctInShelfOrder() {
        var shelf = [issue("Ashfall"), issue("Blackwater")]
        shelf += (1...11).map { issue("Ashfall #\($0)") }
        let entries = LibraryRail.of(shelf, sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.map(\.label) == ["A", "B"])
        #expect(entries[0].publicationID == shelf[0].id)
    }

    /// Uppercased for the reader's locale rather than for the machine's, the rule
    /// ``LibrarySections`` already applies to a heading — so a heading and an index entry
    /// cannot disagree about one row.
    @Test("A Turkish shelf files ısı under I")
    func turkishLocale() {
        var shelf = [issue("ısı")]
        shelf += (1...12).map { issue("Zephyr \($0)") }
        let entries = LibraryRail.of(shelf, sort: .title, locale: Locale(identifier: "tr"))

        #expect(entries.map(\.label) == ["I", "Z"])
    }

    /// The index jumps to a row, and headings change what the shelf draws around that row.
    ///
    /// The list layout divides now — ``LibrarySections/divide(_:by:columns:locale:)`` at one
    /// column — so the rows the rail addresses sit inside sections. Two things have to hold
    /// for a letter to land where it says: the sections are contiguous runs of the same
    /// arranged shelf, so no row moves, and the first row of the section headed by a letter
    /// is the row the rail points at. A regrouping, or an entry pointing at a row in the
    /// middle of its section, would scroll the reader somewhere they did not ask for.
    @Test("With the headings drawn, a letter still jumps to the first row filed under it")
    func jumpTargetsSurviveTheHeadings() {
        let shelf = Array("ABCDEFGHIJKLMNOPQRSTUVWXY").enumerated().flatMap { index, letter in
            (1...(index < 22 ? 2 : 1)).map { issue("\(letter)shfall \($0)") }
        }
        let english = Locale(identifier: "en")
        let sections = LibrarySections.divide(shelf, by: .title, columns: 1, locale: english)
        let entries = LibraryRail.of(shelf, sort: .title, locale: english)

        #expect(shelf.count == 47)
        #expect(sections.count == 25, "the list divides this shelf")
        #expect(entries.map(\.label) == sections.map(\.title))
        for (entry, section) in zip(entries, sections) {
            #expect(entry.publicationID == section.publications.first?.id)
        }
        #expect(sections.flatMap(\.publications).map(\.id) == shelf.map(\.id), "a row moved")
    }
}
