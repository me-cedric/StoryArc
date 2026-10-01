import Foundation
import Testing

import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// `collections-and-reading-lists` task 7.3: a server reading list never joins
/// `Shelves.lists`, so this is what carries "which list, and where in it" from
/// `KavitaListView`'s own row tap to the reader's next/previous offer. Android's
/// `ServerListContextTest` and `ServerListContextIntegrationTest` make the same claims.
/// `.serialized`: every test shares `ServerListContext`'s own single `current`, and the two
/// network tests also share a process-wide registered `URLProtocol` — the same reason
/// `SourceRangeTransportTests` gives for the same trait.
@MainActor
@Suite("Where an entry opened from", .serialized)
struct ServerListContextTests {

    private let serverID = UUID()
    private var server: String { serverID.uuidString }

    private func item(_ chapterId: Int, _ order: Int, pagesRead: Int = 0) throws -> KavitaReadingListItem {
        try JSONDecoder().decode(
            KavitaReadingListItem.self,
            from: Data("""
            {"id": \(chapterId), "order": \(order), "chapterId": \(chapterId), "title": "Issue \(chapterId)",
             "pagesRead": \(pagesRead), "pagesTotal": 22}
            """.utf8)
        )
    }

    private func publication(_ chapterId: Int, on server: UUID? = nil) -> Publication {
        Publication(
            identity: .init(
                serverIdentifier: .init(sourceID: server ?? serverID, remoteID: "chapter:\(chapterId)")
            ),
            format: .cbz,
            displayTitle: "Issue \(chapterId)",
            origin: .authoritative
        )
    }

    private func place(position: Int) throws -> ServerListContext.Place {
        try .init(
            serverId: server,
            serverAddress: KavitaAddress(base: URL(string: "http://localhost:1")!, apiKey: "key"),
            listId: 8,
            entries: [item(10, 0), item(11, 1), item(12, 2)],
            position: position
        )
    }

    @Test("next and previous read the adjacent entries, by position")
    func nextAndPrevious() throws {
        let middle = try place(position: 1)
        #expect(middle.next?.chapterId == 12)
        #expect(middle.previous?.chapterId == 10)
    }

    @Test("next is nil past the last entry, and previous is nil before the first")
    func edges() throws {
        #expect(try place(position: 2).next == nil)
        #expect(try place(position: 0).previous == nil)
    }

    @Test("holds is true only for the publication at this place's own position")
    func holds() throws {
        let middle = try place(position: 1)
        #expect(middle.holds(publication(11)))
        #expect(!middle.holds(publication(10)))
        #expect(!middle.holds(publication(99)))
    }

    @Test("holds is false for a publication from a different server")
    func holdsAnotherServer() throws {
        let middle = try place(position: 1)
        #expect(!middle.holds(publication(11, on: UUID())))
    }

    @Test("next(after:) and previous(before:) answer only when current holds that publication")
    func askingCurrent() throws {
        ServerListContext.opened(try place(position: 1))
        defer { ServerListContext.clear() }

        #expect(ServerListContext.next(after: publication(11))?.identity.serverIdentifier?.remoteID == "chapter:12")
        let previous = ServerListContext.previous(before: publication(11))
        #expect(previous?.identity.serverIdentifier?.remoteID == "chapter:10")
        #expect(ServerListContext.next(after: publication(10)) == nil)
    }

    @Test("the placeholder names the entry before it has been fetched")
    func placeholderNames() throws {
        let named = try place(position: 0).placeholder(of: try item(11, 1))
        #expect(named?.displayTitle == "Issue 11")
        #expect(named?.identity.serverIdentifier?.remoteID == "chapter:11")
    }

    // MARK: - Reaching the server, the way the list view's own row does

    private func place(host: String, position: Int) throws -> ServerListContext.Place {
        try .init(
            serverId: server,
            serverAddress: KavitaAddress(base: #require(URL(string: "http://\(host)")), apiKey: "key"),
            listId: 8,
            entries: [item(10, 0), item(11, 1), item(12, 2)],
            position: position
        )
    }

    private func client(host: String, status: Int, body: Data) throws -> KavitaClient {
        let place = try place(host: host, position: 0)
        return KavitaClient(
            address: place.serverAddress,
            configuration: EntryStub.session(host: host) { request in
                request.url?.path().hasSuffix("Plugin/authenticate") == true
                    ? (200, Data(#"{"username":"ada","token":"t"}"#.utf8))
                    : (status, body)
            }
        )
    }

    @Test("fetching the next entry advances the place and returns the opened publication")
    func fetchAdvances() async throws {
        let comic = try Data(contentsOf: Self.corpus.appending(path: "comics/single-page.cbz"))
        let place = try place(host: "fetches-next.test", position: 0)
        ServerListContext.opened(place)
        defer { ServerListContext.clear() }

        let fetched = await ServerListContext.fetch(
            place,
            try #require(place.next),
            through: try client(host: "fetches-next.test", status: 200, body: comic)
        )

        guard case .opened = fetched else {
            Issue.record("expected the next entry to open")
            return
        }
        #expect(ServerListContext.current?.position == 1)
    }

    @Test("a server that refuses the fetch answers failed, and the place does not move")
    func fetchFailed() async throws {
        let place = try place(host: "refuses-next.test", position: 0)
        ServerListContext.opened(place)
        defer { ServerListContext.clear() }

        let fetched = await ServerListContext.fetch(
            place,
            try #require(place.next),
            through: try client(host: "refuses-next.test", status: 500, body: Data())
        )

        guard case let .failed(reason) = fetched else {
            Issue.record("expected a refused fetch to fail")
            return
        }
        #expect(reason.contains("Issue 11"), "a refused fetch no longer names the entry it could not open")
        #expect(ServerListContext.current?.position == 0)
    }

    // MARK: - Taking the end screen's offer (tasks 7.3 and 7.14)

    @Test("taking the offered entry fetches it, seeds the server's position and advances the place")
    func takingTheOfferFetches() async throws {
        let comic = try Data(contentsOf: Self.corpus.appending(path: "comics/single-page.cbz"))
        let place = try ServerListContext.Place(
            serverId: server,
            serverAddress: KavitaAddress(base: #require(URL(string: "http://takes-offer.test")), apiKey: "key"),
            listId: 8,
            entries: [item(10, 0), item(11, 1, pagesRead: 5)],
            position: 0
        )
        ServerListContext.opened(place)
        defer { ServerListContext.clear() }
        let offered = try #require(ServerListContext.next(after: publication(10)))
        let progress = try ProgressStore.inMemory()

        let opened = await ServerListContext.open(
            offered,
            seeding: progress,
            through: try client(host: "takes-offer.test", status: 200, body: comic)
        )

        guard case let .opened(publication, _) = opened else {
            Issue.record("taking the offer did not fetch the entry it named")
            return
        }
        #expect(ServerListContext.current?.position == 1)
        let seeded = try await progress.progress(for: publication.identity)
        #expect(seeded != nil, "the taken entry opened without the position the server reported for it")
    }

    @Test("an offer that names no entry of the current list opens nothing")
    func foreignOfferOpensNothing() async throws {
        ServerListContext.opened(try place(position: 0))
        defer { ServerListContext.clear() }

        let opened = await ServerListContext.open(publication(11, on: UUID()), seeding: nil)

        #expect(opened == nil)
    }

    // MARK: - What an end screen offers (task 7.14)

    private func local(_ title: String) -> Publication {
        Publication(
            identity: .init(normalizedPath: "/library/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            origin: .authoritative
        )
    }

    @Test("a list's next row with no file on this device is not offered")
    func noFileIsNotOffered() {
        let reading = local("A")
        let away = publication(41)
        let model = LibraryModel()
        model.publications = [reading, away]
        model.locations[reading.id] = URL(filePath: "/library/A.cbz")
        model.shelves = Shelves(lists: [ReadingList(name: "Crossover", entries: [reading.id, away.id])])

        #expect(model.next(after: reading)?.id == away.id, "the library's own next is the row with no file")
        #expect(model.offeredNext(after: reading) == nil, "a row with no file was offered, and taking it opens nothing")
    }

    @Test("a list's next and previous rows with a file are offered")
    func fileIsOffered() {
        let first = local("A")
        let second = local("B")
        let model = LibraryModel()
        model.publications = [first, second]
        model.locations[first.id] = URL(filePath: "/library/A.cbz")
        model.locations[second.id] = URL(filePath: "/library/B.cbz")
        model.shelves = Shelves(lists: [ReadingList(name: "Crossover", entries: [first.id, second.id])])

        #expect(model.offeredNext(after: first)?.id == second.id)
        #expect(model.offeredPrevious(before: second)?.id == first.id)
    }

    @Test("the server list the reader is inside answers before the library")
    func serverListAnswersFirst() throws {
        let reading = publication(10)
        let other = local("B")
        let model = LibraryModel()
        model.publications = [reading, other]
        model.locations[other.id] = URL(filePath: "/library/B.cbz")
        model.shelves = Shelves(lists: [ReadingList(name: "Crossover", entries: [reading.id, other.id])])
        ServerListContext.opened(try place(position: 0))
        defer { ServerListContext.clear() }

        #expect(model.offeredNext(after: reading)?.identity.serverIdentifier?.remoteID == "chapter:11")
    }

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()
}
