import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// `library-browsing`, *Sectioning a long library*, *An index down the side of a long
/// shelf* and *A sort no letter describes*, over the Mac copies of the iOS rules.
@Suite("Shelf sections and index")
struct ShelfSectionTests {
    private let english = Locale(identifier: "en")

    private func titled(_ title: String, series: String? = nil, year: Int? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(title).cbz"), format: .cbz,
            displayTitle: title, series: series, year: year, origin: .inferred
        )
    }

    /// Fifteen titles under five letters, already in title order.
    private var shelf: [Publication] {
        ["Abyss", "Akira", "Atlas", "Bone", "Blame", "Berserk", "Monster", "Mars", "Maus",
         "Saga", "The Sandman", "Swamp Thing", "Zot", "Zatanna", "Zero"].map { titled($0) }
    }

    @Test("A long shelf sorted by title divides by initial, the article ignored, in the shelf's order")
    func byTitle() {
        let sections = ShelfSections.divide(shelf, by: .title, columns: 3, locale: english)
        #expect(sections.map(\.title) == ["A", "B", "M", "S", "Z"])
        #expect(sections[3].publications.map(\.displayTitle) == ["Saga", "The Sandman", "Swamp Thing"])
        #expect(sections.flatMap(\.publications).map(\.id) == shelf.map(\.id), "the sections reordered the shelf")
    }

    @Test("A sort no letter describes draws no index and no sections, and both return with the title sort")
    func continuousSorts() {
        for sort in [LibrarySort.lastRead, .progress, .dateAdded, .fileSize] {
            #expect(ShelfSections.divide(shelf, by: sort, columns: 1, locale: english).isEmpty, "\(sort)")
            #expect(ShelfSections.index(shelf, sort: sort, locale: english).isEmpty, "\(sort)")
        }
        #expect(ShelfSections.index(shelf, sort: .year, locale: english).isEmpty)
        #expect(!ShelfSections.index(shelf, sort: .title, locale: english).isEmpty)
    }

    @Test("A short shelf has neither; a grid refuses headings that do not earn a row, a list takes them")
    func earnsItsRow() {
        #expect(ShelfSections.divide(Array(shelf.prefix(12)), by: .title, columns: 1, locale: english).isEmpty)
        #expect(ShelfSections.index(Array(shelf.prefix(12)), sort: .title, locale: english).isEmpty)
        #expect(ShelfSections.divide(shelf, by: .title, columns: 4, locale: english).isEmpty)
        #expect(ShelfSections.divide(shelf, by: .title, columns: 1, locale: english).count == 5)
    }

    @Test("The index holds one entry per letter, at the first row filed there, and # for the rest")
    func index() {
        let shelf = [titled("2000 AD"), titled("300")] + self.shelf
        let entries = ShelfSections.index(shelf, sort: .title, locale: english)
        #expect(entries.map(\.label) == ["#", "A", "B", "M", "S", "Z"])
        #expect(entries.first { $0.label == "S" }?.publicationID == self.shelf[9].id)
    }

    @Test("Sorted by series, a series the shelf holds more than one of is its own heading, the rest Other")
    func bySeries() {
        let saga = (1...7).map { titled("Saga \($0)", series: "Saga") }
        let maus = (1...5).map { titled("Maus \($0)", series: "Maus") }
        let loose = [titled("One"), titled("Two"), titled("Three")]
        let sections = ShelfSections.divide(maus + saga + loose, by: .series, columns: 3, locale: english)
        #expect(sections.map(\.title) == ["Maus", "Saga", String(localized: "desktop.library.section.other")])
    }

    @Test("A rail too short for every letter keeps an even spread with the first and the last")
    func collapsedRail() {
        let entries = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { ShelfIndexEntry(label: String($0), publicationID: String($0)) }
        let kept = ShelfIndexRail.collapsed(entries, toFit: ShelfIndexRail.entryHeight * 10)
        #expect(kept.count == 10)
        #expect(kept.first?.label == "A" && kept.last?.label == "Z")
        #expect(ShelfIndexRail.collapsed(entries, toFit: 2_000).count == 26)
    }
}
