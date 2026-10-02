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
        publisher: String? = nil,
        format: PublicationFormat = .cbz,
        year: Int? = nil,
        language: String? = nil,
        genres: [String] = [],
        tags: [String] = [],
        fileSize: Int64? = nil,
        addedAt: Date? = nil,
        source: UUID? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/\(title)"),
            format: format,
            displayTitle: title,
            series: series,
            number: number,
            authors: authors,
            publisher: publisher,
            year: year,
            language: language,
            genres: genres,
            tags: tags,
            origin: .inferred,
            sourceID: source,
            fileSize: fileSize,
            addedAt: addedAt
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

    @Test("A publication with no series sorts after every publication that has one")
    func seriesSortPutsStandalonesLast() {
        // "Zephyr" used to sort by its title *among* the series names, landing between
        // "Ashfall" and "Blackwater" — which splits the standalone pile in two and stops a
        // sectioned shelf from dividing at all.
        let library = [
            publication("Blackwater #1", series: "Blackwater", number: "1"),
            publication("Zephyr"),
            publication("Ashfall #2", series: "Ashfall", number: "2"),
            publication("Ashfall #1", series: "Ashfall", number: "1"),
            publication("Almanac")
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(titles(sorted) == ["Ashfall #1", "Ashfall #2", "Blackwater #1", "Almanac", "Zephyr"])
    }

    @Test("An empty series and a whitespace series are both no series")
    func blankSeriesSortsWithTheStandalones() {
        // A real `ComicInfo.xml` writes all three for a book that belongs to no series.
        let library = [
            publication("Blank", series: ""),
            publication("Ashfall #1", series: "Ashfall", number: "1"),
            publication("Spaces", series: "   "),
            publication("Absent")
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(titles(sorted) == ["Ashfall #1", "Absent", "Blank", "Spaces"])
    }

    @Test("Descending keeps the standalones together, at the other end")
    func seriesSortDescendingKeepsStandalonesContiguous() {
        // The pile has to stay one contiguous run whichever way the shelf runs, because
        // that is what lets it be drawn under a single heading.
        let library = [
            publication("Ashfall #1", series: "Ashfall", number: "1"),
            publication("Zephyr"),
            publication("Blackwater #1", series: "Blackwater", number: "1"),
            publication("Almanac")
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(sort: .series, ascending: false), locale: english
        )
        #expect(titles(sorted) == ["Zephyr", "Almanac", "Blackwater #1", "Ashfall #1"])
    }

    @Test("Date added puts the newest first, and never-dated last")
    func dateAddedSort() {
        let library = [
            publication("Maus"),
            publication("Bone", addedAt: Date(timeIntervalSince1970: 100)),
            publication("Akira", addedAt: Date(timeIntervalSince1970: 300)),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(sort: .dateAdded), locale: english
        )
        #expect(titles(sorted) == ["Akira", "Bone", "Maus"])
    }

    @Test("File size puts the largest first, and unweighed last")
    func fileSizeSort() {
        let library = [
            publication("Maus"),
            publication("Bone", fileSize: 100),
            publication("Akira", fileSize: 300),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(sort: .fileSize), locale: english
        )
        #expect(titles(sorted) == ["Akira", "Bone", "Maus"])
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

    @Test("A genre or a tag match surfaces a publication that the title, series and author do not")
    func searchMatchesTagsAndGenres() {
        let library = [
            publication("Watchmen", genres: ["Noir"]),
            publication("Akira", tags: ["Cyberpunk"]),
            publication("Bone"),
        ]
        #expect(titles(LibraryIndex.arrange(library, query: LibraryQuery(search: "noir"), locale: english)) == ["Watchmen"])
        #expect(titles(LibraryIndex.arrange(library, query: LibraryQuery(search: "cyberpunk"), locale: english)) == ["Akira"])
    }

    @Test("A tag or a genre match groups with the publisher match, not with the title")
    func tagMatchGroupsWithPublisher() {
        let library = [
            publication("Watchmen", publisher: "Noir Press"),
            publication("Akira", tags: ["Noir"]),
        ]
        let groups = LibraryIndex.grouped(library, query: LibraryQuery(search: "noir"), locale: english)
        #expect(groups.map(\.kind) == [.tag])
        #expect(Set(titles(groups.first?.publications ?? [])) == ["Watchmen", "Akira"])
    }

    // Filter-group tests moved to `LibraryFilterTests.swift` to stay under the
    // 400-line cap.
}
