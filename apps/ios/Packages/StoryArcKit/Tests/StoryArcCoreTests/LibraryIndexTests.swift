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
            origin: .inferred,
            sourceID: source
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

    // MARK: - Scope

    private static let folder = UUID()
    private static let server = UUID()

    private var mixedLibrary: [Publication] {
        [
            publication("Akira", source: Self.folder),
            publication("Bone", source: Self.server),
            publication("Maus"),
        ]
    }

    @Test("The library spans every source until it is narrowed to one")
    func scopeSpansSources() {
        let sorted = LibraryIndex.arrange(mixedLibrary, query: LibraryQuery(), locale: english)
        #expect(titles(sorted) == ["Akira", "Bone", "Maus"])
    }

    @Test("A scope shows one source and hides the rest")
    func scopeNarrows() {
        let query = LibraryQuery(scope: .source(Self.server))
        #expect(titles(LibraryIndex.arrange(mixedLibrary, query: query, locale: english)) == ["Bone"])
    }

    @Test("A scope narrows the search as well as the shelf")
    func scopeNarrowsSearch() {
        // "o" is in Bone and in Maus... and only Bone is on the server.
        let query = LibraryQuery(search: "o", scope: .source(Self.server))
        #expect(titles(LibraryIndex.arrange(mixedLibrary, query: query, locale: english)) == ["Bone"])
    }

    @Test("A publication no source claims belongs only to the whole library")
    func unattributedIsOnlyInAllSources() {
        let orphan = publication("Maus")
        #expect(LibraryScope.allSources.contains(orphan))
        #expect(!LibraryScope.source(Self.folder).contains(orphan))
    }

    @Test("A scope survives a round trip through storage")
    func scopeStorageKey() {
        #expect(LibraryScope.allSources.storageKey == "all")
        #expect(LibraryScope(storageKey: "all") == .allSources)

        let scoped = LibraryScope.source(Self.server)
        #expect(LibraryScope(storageKey: scoped.storageKey) == scoped)
    }

    @Test("A stored scope naming nothing recognisable opens the whole library")
    func scopeFallsBack() {
        // Never an empty shelf with nothing to explain it: the reader did not remove
        // anything they can see, and "all sources" is the answer that is never wrong.
        #expect(LibraryScope(storageKey: "not-a-uuid") == .allSources)

        let registry = SourceRegistry(sources: [Source(displayName: "Comics", kind: .localFolder)])
        #expect(LibraryScope.source(Self.server).resolved(in: registry) == .allSources)
    }

    @Test("A scope whose source is still there is left alone")
    func scopeSurvivesResolution() {
        let source = Source(displayName: "Kavita", kind: .kavitaServer)
        let registry = SourceRegistry(sources: [source])
        #expect(LibraryScope.source(source.id).resolved(in: registry) == .source(source.id))
    }

    @Test("A source is named on a row only when there is more than one")
    func attribution() {
        let one = Source(displayName: "Comics", kind: .localFolder)
        let two = Source(displayName: "Kavita", kind: .kavitaServer)

        #expect(!SourceRegistry(sources: [one]).attributesPublications)
        #expect(SourceRegistry(sources: [one, two]).attributesPublications)
        #expect(SourceRegistry(sources: [one, two]).name(of: two.id) == "Kavita")
        #expect(SourceRegistry(sources: [one, two]).name(of: nil) == nil)
    }

    @Test("The scopes on offer are every source, in the reader's own order")
    func scopesOffered() {
        let one = Source(displayName: "Comics", kind: .localFolder)
        let two = Source(displayName: "Kavita", kind: .kavitaServer)
        #expect(
            SourceRegistry(sources: [one, two]).scopes
                == [.allSources, .source(one.id), .source(two.id)]
        )
    }

    @Test("A query stored before scopes existed still decodes")
    func queryDecodesWithoutScope() throws {
        // The build that added the scope must be able to read what the one before it
        // wrote, or a reader opens the app to find every filter they set silently gone.
        let stored = """
        {"search":"","readStates":["unread"],"formats":[],\
        "languages":[],"sort":"title","ascending":true}
        """
        let decoded = try JSONDecoder().decode(LibraryQuery.self, from: Data(stored.utf8))
        #expect(decoded.scope == .allSources)
        #expect(decoded.readStates == [.unread])
    }

    // MARK: - Search grouping

    @Test("Results are grouped by why they matched")
    func groupedByMatchKind() throws {
        let library = [
            publication("Sandman Mystery Theatre"),
            publication("Preludes", series: "The Sandman"),
            publication("Endless Nights", publisher: "Sandman Press"),
        ]
        let groups = LibraryIndex.grouped(
            library,
            query: LibraryQuery(search: "sandman"),
            locale: english
        )

        #expect(groups.map(\.kind) == [.publication, .series, .tag])
        #expect(titles(groups[0].publications) == ["Sandman Mystery Theatre"])
        #expect(titles(groups[1].publications) == ["Preludes"])
        #expect(titles(groups[2].publications) == ["Endless Nights"])
    }

    @Test("An author match is a person, and headings follow the best match")
    func groupedByPerson() {
        let library = [
            publication("Signal to Noise", authors: ["Neil Gaiman"]),
            publication("Gaiman Reader"),
        ]
        let groups = LibraryIndex.grouped(
            library,
            query: LibraryQuery(search: "gaiman"),
            locale: english
        )
        #expect(groups.map(\.kind) == [.publication, .person])
    }

    @Test("A publication that matches twice appears once, under its best match")
    func groupedOnce() {
        let library = [publication("Alan's Diary", authors: ["Alan Moore"])]
        let groups = LibraryIndex.grouped(
            library,
            query: LibraryQuery(search: "alan"),
            locale: english
        )
        #expect(groups.map(\.kind) == [.publication])
        #expect(groups.flatMap(\.publications).count == 1)
    }

    @Test("Nothing typed means no headings rather than one saying Titles")
    func groupedNeedsAQuery() {
        #expect(LibraryIndex.grouped(mixedLibrary, query: LibraryQuery(), locale: english).isEmpty)
    }

    @Test("Grouping obeys the scope, because it groups what the shelf already shows")
    func groupedRespectsScope() {
        let library = [
            publication("Bone", source: Self.folder),
            publication("Bone Sharps", source: Self.server),
        ]
        let query = LibraryQuery(search: "bone", scope: .source(Self.server))
        let groups = LibraryIndex.grouped(library, query: query, locale: english)
        #expect(groups.flatMap { titles($0.publications) } == ["Bone Sharps"])
    }
}
