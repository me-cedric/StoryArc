import Foundation
import Testing

@testable import StoryArcCore

/// The browsing rules, asserted against the same table as Android's
/// `LibraryIndexTest`.
///
/// `library-browsing` has to behave identically on both platforms, and two
/// independent implementations (ADR-0001) only stay honest if the same cases are
/// put to both. Add a case here, add it there.
@Suite("Library browsing")
struct LibraryIndexTests {

    private func publication(
        _ title: String,
        series: String? = nil,
        number: String? = nil,
        authors: [String] = [],
        format: PublicationFormat = .cbz,
        year: Int? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/\(title)"),
            format: format,
            displayTitle: title,
            series: series,
            number: number,
            authors: authors,
            year: year,
            origin: .inferred
        )
    }

    private func titles(_ publications: [Publication]) -> [String] {
        publications.map(\.displayTitle)
    }

    private let english = Locale(identifier: "en")

    // MARK: - Leading articles

    @Test("An English leading article does not decide where a title files")
    func englishArticle() {
        #expect(LibraryIndex.sortKey("The Sandman", locale: english) == "Sandman")
        #expect(LibraryIndex.sortKey("A Contract with God", locale: english) == "Contract with God")
    }

    @Test("An article in another language is left alone")
    func articleIsPerLanguage() {
        // "La" is an article in Spanish and part of the name in English.
        #expect(LibraryIndex.sortKey("La Brea", locale: english) == "La Brea")
        #expect(LibraryIndex.sortKey("La Brea", locale: Locale(identifier: "es")) == "Brea")
    }

    @Test("The French apostrophe form carries no space")
    func frenchElision() {
        #expect(LibraryIndex.sortKey("L'Étranger", locale: Locale(identifier: "fr")) == "Étranger")
    }

    @Test("A title that is only an article keeps it")
    func articleAlone() {
        #expect(LibraryIndex.sortKey("The", locale: english) == "The")
    }

    // MARK: - Sorting

    @Test("Titles sort by their key, not their first letter")
    func titleSort() {
        let library = [publication("The Sandman"), publication("Akira"), publication("Bone")]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(), locale: english)
        #expect(titles(sorted) == ["Akira", "Bone", "The Sandman"])
    }

    @Test("Descending reverses the order")
    func descending() {
        let library = [publication("Akira"), publication("Bone")]
        let sorted = LibraryIndex.arrange(
            library,
            query: LibraryQuery(sort: .title, ascending: false),
            locale: english
        )
        #expect(titles(sorted) == ["Bone", "Akira"])
    }

    @Test("A series sorts by issue number, numerically")
    func seriesSort() {
        let library = [
            publication("Bone #10", series: "Bone", number: "10"),
            publication("Bone #9", series: "Bone", number: "9"),
            publication("Bone #2", series: "Bone", number: "2"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(titles(sorted) == ["Bone #2", "Bone #9", "Bone #10"])
    }

    // MARK: - Search

    @Test("A title that starts with the query outranks an author who contains it")
    func searchRanking() {
        let library = [
            publication("Watchmen", authors: ["Alan Moore"]),
            publication("Alan's Diary", authors: ["Someone Else"]),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(search: "alan"), locale: english)
        #expect(titles(sorted) == ["Alan's Diary", "Watchmen"])
    }

    @Test("A query that matches nothing returns nothing rather than everything")
    func searchMisses() {
        let library = [publication("Akira"), publication("Bone")]
        #expect(LibraryIndex.arrange(library, query: LibraryQuery(search: "zzz")).isEmpty)
    }

    // MARK: - Filters

    @Test("Filters combine with AND")
    func filtersCombine() {
        let library = [publication("Akira", format: .cbz), publication("Bone", format: .pdf)]
        let query = LibraryQuery(search: "o", formats: [.cbz])
        #expect(LibraryIndex.arrange(library, query: query, locale: english).isEmpty)
    }

    @Test("A filter group counts once however many values it holds")
    func filterBadge() {
        let query = LibraryQuery(readStates: [.unread], formats: [.cbz, .cbr, .pdf])
        #expect(query.activeFilterCount == 2)
    }

    @Test("Read state filters on what the progress store says")
    func readStateFilter() {
        let akira = publication("Akira")
        let bone = publication("Bone")
        let states: [String: LibraryIndex.Progress] = [
            akira.id: .init(state: .finished, fraction: 1, lastReadAt: Date(timeIntervalSince1970: 10)),
            bone.id: .init(state: .inProgress, fraction: 0.5, lastReadAt: Date(timeIntervalSince1970: 20)),
        ]
        let sorted = LibraryIndex.arrange(
            [akira, bone],
            query: LibraryQuery(readStates: [.inProgress]),
            locale: english
        ) { states[$0.id] ?? .unread }
        #expect(titles(sorted) == ["Bone"])
    }


    // MARK: - Next in series

    @Test("The next issue is the one after this number, not the next row")
    func nextInSeries() throws {
        let library = [
            publication("Bone #10", series: "Bone", number: "10"),
            publication("Bone #2", series: "Bone", number: "2"),
            publication("Bone #9", series: "Bone", number: "9"),
            publication("Akira", series: "Akira", number: "1"),
        ]
        let second = try #require(library.first { $0.number == "2" })
        let next = LibraryIndex.next(after: second, in: library)
        #expect(next?.displayTitle == "Bone #9")
    }

    @Test("The last issue in a series has no next")
    func lastInSeries() throws {
        let library = [
            publication("Bone #1", series: "Bone", number: "1"),
            publication("Bone #2", series: "Bone", number: "2"),
        ]
        let last = try #require(library.last)
        #expect(LibraryIndex.next(after: last, in: library) == nil)
    }

    @Test("A publication with no series has no next, however many neighbours it has")
    func noSeriesNoNext() {
        let alone = publication("Watchmen")
        #expect(LibraryIndex.next(after: alone, in: [alone, publication("Akira")]) == nil)
    }

    // MARK: - Continue reading

    @Test("Continue reading holds only what is in progress, most recent first")
    func continueRow() {
        let akira = publication("Akira")
        let bone = publication("Bone")
        let maus = publication("Maus")
        let states: [String: LibraryIndex.Progress] = [
            akira.id: .init(state: .inProgress, fraction: 0.2, lastReadAt: Date(timeIntervalSince1970: 100)),
            bone.id: .init(state: .inProgress, fraction: 0.8, lastReadAt: Date(timeIntervalSince1970: 300)),
            maus.id: .init(state: .finished, fraction: 1, lastReadAt: Date(timeIntervalSince1970: 400)),
        ]
        let row = LibraryIndex.continueReading([akira, bone, maus]) { states[$0.id] ?? .unread }
        #expect(titles(row) == ["Bone", "Akira"])
    }

    @Test("Continue reading is empty rather than a header over a gap")
    func continueRowEmpty() {
        #expect(LibraryIndex.continueReading([publication("Akira")]) { _ in .unread }.isEmpty)
    }
}
