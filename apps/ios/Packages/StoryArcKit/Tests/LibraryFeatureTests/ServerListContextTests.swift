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

    private let server = UUID().uuidString

    private func item(_ chapterId: Int, _ order: Int) -> KavitaReadingListItem {
        try! JSONDecoder().decode(
            KavitaReadingListItem.self,
            from: Data("""
            {"id": \(chapterId), "order": \(order), "chapterId": \(chapterId), "title": "Issue \(chapterId)"}
            """.utf8)
        )
    }

    private func publication(_ chapterId: Int, on server: String? = nil) -> Publication {
        Publication(
            identity: .init(
                serverIdentifier: .init(sourceID: UUID(uuidString: server ?? self.server)!, remoteID: "chapter:\(chapterId)")
            ),
            format: .cbz,
            displayTitle: "Issue \(chapterId)",
            origin: .authoritative
        )
    }

    private func place(position: Int) -> ServerListContext.Place {
        .init(
            serverId: server,
            serverAddress: KavitaAddress(base: URL(string: "http://localhost:1")!, apiKey: "key"),
            listId: 8,
            entries: [item(10, 0), item(11, 1), item(12, 2)],
            position: position
        )
    }

    @Test("next and previous read the adjacent entries, by position")
    func nextAndPrevious() {
        let middle = place(position: 1)
        #expect(middle.next?.chapterId == 12)
        #expect(middle.previous?.chapterId == 10)
    }

    @Test("next is nil past the last entry, and previous is nil before the first")
    func edges() {
        #expect(place(position: 2).next == nil)
        #expect(place(position: 0).previous == nil)
    }

    @Test("holds is true only for the publication at this place's own position")
    func holds() {
        let middle = place(position: 1)
        #expect(middle.holds(publication(11)))
        #expect(!middle.holds(publication(10)))
        #expect(!middle.holds(publication(99)))
    }

    @Test("holds is false for a publication from a different server")
    func holdsAnotherServer() {
        let middle = place(position: 1)
        #expect(!middle.holds(publication(11, on: UUID().uuidString)))
    }

    @Test("next(after:) and previous(before:) answer only when current holds that publication")
    func askingCurrent() {
        ServerListContext.opened(place(position: 1))
        defer { ServerListContext.clear() }

        #expect(ServerListContext.next(after: publication(11))?.identity.serverIdentifier?.remoteID == "chapter:12")
        #expect(ServerListContext.previous(before: publication(11))?.identity.serverIdentifier?.remoteID == "chapter:10")
        #expect(ServerListContext.next(after: publication(10)) == nil)
    }

    @Test("the placeholder names the entry before it has been fetched")
    func placeholderNames() {
        let named = place(position: 0).placeholder(of: item(11, 1))
        #expect(named?.displayTitle == "Issue 11")
        #expect(named?.identity.serverIdentifier?.remoteID == "chapter:11")
    }

    // MARK: - Reaching the server, the way the list view's own row does

    private func place(host: String, position: Int) -> ServerListContext.Place {
        .init(
            serverId: server,
            serverAddress: KavitaAddress(base: URL(string: "http://\(host)")!, apiKey: "key"),
            listId: 8,
            entries: [item(10, 0), item(11, 1), item(12, 2)],
            position: position
        )
    }

    private func client(host: String, status: Int, body: Data) -> KavitaClient {
        let place = place(host: host, position: 0)
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
        let place = place(host: "fetches-next.test", position: 0)
        ServerListContext.opened(place)
        defer { ServerListContext.clear() }

        let fetched = await ServerListContext.fetch(
            place,
            try #require(place.next),
            through: client(host: "fetches-next.test", status: 200, body: comic)
        )

        guard case .opened = fetched else {
            Issue.record("expected the next entry to open")
            return
        }
        #expect(ServerListContext.current?.position == 1)
    }

    @Test("a server that refuses the fetch answers failed, and the place does not move")
    func fetchFailed() async throws {
        let place = place(host: "refuses-next.test", position: 0)
        ServerListContext.opened(place)
        defer { ServerListContext.clear() }

        let fetched = await ServerListContext.fetch(
            place,
            try #require(place.next),
            through: client(host: "refuses-next.test", status: 500, body: Data())
        )

        #expect(fetched == .failed)
        #expect(ServerListContext.current?.position == 0)
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
