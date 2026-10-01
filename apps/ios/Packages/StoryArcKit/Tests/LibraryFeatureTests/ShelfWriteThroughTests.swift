import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// 10.15: a removed source's rows must not come back from the cached shelf at the next
/// launch. `remove(_:credentials:)` dropped the rows from `publications` but never wrote the
/// snapshot, so the old cache put them straight back, and the launch scan — which never
/// removes a row of a source it did not walk — wrote them into the snapshot again. They
/// never went.
@Suite("A removed source's rows do not come back from the cache")
@MainActor
struct ShelfWriteThroughTests {
    private func documents() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "write-through-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func publication(_ path: String, title: String, sourceID: UUID? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: path),
            format: .cbz,
            displayTitle: title,
            origin: .inferred,
            sourceID: sourceID
        )
    }

    @Test("Removing a server source writes the shelf through, so its row does not come back")
    func removingAServerWritesTheShelfThrough() throws {
        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }
        let cache = LibraryCache(directory: stand)

        let first = LibraryModel(documents: stand, cache: cache)
        let server = Source(displayName: "Kavita", kind: .kavitaServer, locator: "https://kavita.example")
        first.add(server)
        first.publications = [
            publication("/gone.cbz", title: "Gone", sourceID: server.id),
            publication("/kept.cbz", title: "Kept"),
        ]

        first.remove(server, credentials: nil)

        let second = LibraryModel(documents: stand, cache: cache)
        second.restoreCachedLibrary()

        #expect(second.publications.map(\.displayTitle) == ["Kept"])
    }
}
