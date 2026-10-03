import Foundation
import Testing

@testable import StoryArcCore

/// Filter-group behaviour for `library-browsing`, split out of
/// `LibraryIndexTests` to stay under the line cap.
///
/// Asserted against the same table as Android's `LibraryIndexTest`. Add a
/// case here, add it there.
@Suite("Library browsing filters")
struct LibraryFilterTests {

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
        status: PublicationStatus? = nil,
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
            status: status,
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

    @Test("Every group counts, and the year range counts once for both its ends")
    func everyGroupCounts() {
        let query = LibraryQuery(
            readStates: [.unread],
            formats: [.cbz],
            languages: ["en"],
            publishers: ["DC"],
            genres: ["Superhero"],
            tags: ["Reprint"],
            statuses: [.ongoing],
            years: YearRange(from: 1986, to: 1999)
        )
        #expect(query.activeFilterCount == 8)
    }

    @Test("Clearing keeps the search and the sort and drops every group")
    func clearingKeepsSearchAndSort() {
        let query = LibraryQuery(
            search: "bone",
            readStates: [.unread],
            formats: [.cbz],
            languages: ["en"],
            publishers: ["DC"],
            genres: ["Superhero"],
            tags: ["Reprint"],
            statuses: [.ongoing],
            years: YearRange(from: 1986),
            sort: .lastRead,
            ascending: false
        )
        let cleared = query.withoutFilters
        #expect(cleared.activeFilterCount == 0)
        #expect(cleared.search == "bone")
        #expect(cleared.sort == .lastRead)
        #expect(cleared.ascending == false)
    }

    @Test("A publisher filter keeps only what that publisher put out")
    func publisherFilter() {
        let library = [
            publication("Watchmen", publisher: "DC"),
            publication("Akira", publisher: "Kodansha"),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(publishers: ["DC"]), locale: english
        )
        #expect(titles(sorted) == ["Watchmen"])
    }

    @Test("Two publishers ticked means either, not both")
    func publishersAreAlternatives() {
        let library = [
            publication("Watchmen", publisher: "DC"),
            publication("Akira", publisher: "Kodansha"),
            publication("Bone", publisher: "Cartoon Books"),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(publishers: ["DC", "Kodansha"]), locale: english
        )
        #expect(titles(sorted) == ["Akira", "Watchmen"])
    }

    @Test("A language filter keeps only that language")
    func languageFilter() {
        let library = [
            publication("Akira", language: "ja"),
            publication("Bone", language: "en"),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(languages: ["ja"]), locale: english
        )
        #expect(titles(sorted) == ["Akira"])
    }

    @Test("A genre filter keeps a publication that carries the genre among others")
    func genreFilter() {
        let library = [
            publication("Watchmen", genres: ["Superhero", "Mystery"]),
            publication("Maus", genres: ["Biography"]),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(genres: ["Mystery"]), locale: english
        )
        #expect(titles(sorted) == ["Watchmen"])
    }

    @Test("Genre and tag are separate groups, so they combine with AND")
    func genreAndTagCombine() {
        let both = publication("Watchmen", genres: ["Superhero"], tags: ["Reprint"])
        let genreOnly = publication("Batman", genres: ["Superhero"], tags: ["Annual"])
        let query = LibraryQuery(genres: ["Superhero"], tags: ["Reprint"])
        let sorted = LibraryIndex.arrange([both, genreOnly], query: query, locale: english)
        #expect(titles(sorted) == ["Watchmen"])
    }

    @Test("A status filter keeps only what carries that status")
    func statusFilter() {
        let library = [
            publication("Watchmen", status: .completed),
            publication("Saga", status: .ongoing),
            publication("Maus", status: nil),
        ]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(statuses: [.completed]), locale: english
        )
        #expect(titles(sorted) == ["Watchmen"])
    }

    @Test("A publication with no status at all never matches an active status filter")
    func statusFilterExcludesUnset() {
        let library = [publication("Maus", status: nil)]
        let sorted = LibraryIndex.arrange(
            library, query: LibraryQuery(statuses: [.ongoing]), locale: english
        )
        #expect(sorted.isEmpty)
    }

    @Test("A year range keeps what came out inside it, both ends included")
    func yearRangeFilter() {
        let library = [
            publication("Watchmen", year: 1986),
            publication("Bone", year: 1991),
            publication("Persepolis", year: 2000),
        ]
        let query = LibraryQuery(years: YearRange(from: 1986, to: 1991))
        let sorted = LibraryIndex.arrange(library, query: query, locale: english)
        #expect(titles(sorted) == ["Bone", "Watchmen"])
    }

    @Test("One end of a range is enough")
    func openEndedYearRange() {
        let library = [publication("Watchmen", year: 1986), publication("Persepolis", year: 2000)]
        let from = LibraryIndex.arrange(
            library, query: LibraryQuery(years: YearRange(from: 1990)), locale: english
        )
        #expect(titles(from) == ["Persepolis"])
        let upTo = LibraryIndex.arrange(
            library, query: LibraryQuery(years: YearRange(to: 1990)), locale: english
        )
        #expect(titles(upTo) == ["Watchmen"])
    }

    @Test("A publication with no year is outside an active range, not before it")
    func unknownYearIsOutsideARange() {
        let library = [publication("Undated"), publication("Watchmen", year: 1986)]
        let query = LibraryQuery(years: YearRange(to: 2000))
        #expect(titles(LibraryIndex.arrange(library, query: query, locale: english)) == ["Watchmen"])
        // And still there when no range is set, which is what "no opinion" means.
        #expect(LibraryIndex.arrange(library, query: LibraryQuery(), locale: english).count == 2)
    }

    @Test("Every group narrows the same list at once")
    func everyGroupCombines() {
        let match = publication(
            "Watchmen",
            publisher: "DC",
            format: .cbz,
            year: 1986,
            language: "en",
            genres: ["Superhero"],
            tags: ["Reprint"]
        )
        // Identical but for the publisher, which is enough to drop it.
        let miss = publication(
            "Watchmen Companion",
            publisher: "Marvel",
            format: .cbz,
            year: 1986,
            language: "en",
            genres: ["Superhero"],
            tags: ["Reprint"]
        )
        let query = LibraryQuery(
            formats: [.cbz],
            languages: ["en"],
            publishers: ["DC"],
            genres: ["Superhero"],
            tags: ["Reprint"],
            years: YearRange(from: 1980, to: 1989)
        )
        let sorted = LibraryIndex.arrange([match, miss], query: query, locale: english)
        #expect(titles(sorted) == ["Watchmen"])
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
}
