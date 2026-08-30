import Foundation
import Testing

@testable import StoryArcCore

/// One library across every source, and search results grouped by why they matched.
///
/// Split from `LibraryIndexTests.swift`, which had reached the 400-line cap. Android's
/// `LibraryIndexTest` holds the same cases.
@Suite("Library scope and grouping")
struct LibraryScopeTests {

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

    private static let server = UUID()
    private static let folder = UUID()

    private var mixedLibrary: [Publication] {
        [
            publication("Akira", source: Self.folder),
            publication("Bone", source: Self.server),
            publication("Maus"),
        ]
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

    @Test("The library spans every source until it is narrowed to one")
    func scopeSpansSources() {
        let sorted = LibraryIndex.arrange(mixedLibrary, query: LibraryQuery(), locale: english)
        #expect(titles(sorted) == ["Akira", "Bone", "Maus"])
    }
}
