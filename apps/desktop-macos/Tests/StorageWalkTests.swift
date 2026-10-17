import Formats
import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// Task 3.15's walk: each store of the running app filled, then cleared from the
    /// preferences' own model, one at a time, and the other two left as they were.
    @MainActor
    @Suite("Storage walk")
    struct StorageWalkTests {
        @Test("Downloads, covers and reading records are each measured and cleared on their own")
        func clearsEach() async throws {
            let library = try await Walk.fixtureLibrary()
            let storage = library.storage
            try await fill(library)
            await storage.refresh()
            let before = storage.sizes
            ConformanceLog.note("storage before", "\(before)")
            for store in MacStorage.Store.allCases {
                #expect(before[store] > 0, "\(store) held nothing to clear")
            }
            for store in MacStorage.Store.allCases {
                let others = MacStorage.Store.allCases.filter { $0 != store && storage.sizes[$0] > 0 }
                await storage.clear(store)
                if store == .records {
                    // The records live in a database file that keeps its pages after a delete,
                    // so its size does not drop at once; what was in it is what must be gone.
                    let left = try await library.progress?.recent(limit: 10) ?? []
                    #expect(left.isEmpty, "reading records were left after the clear")
                } else {
                    #expect(storage.sizes[store] < before[store], "\(store) was not cleared")
                }
                for other in others {
                    #expect(storage.sizes[other] > 0, "clearing \(store) cleared \(other) too")
                }
            }
            ConformanceLog.note("storage after", "\(storage.sizes)")
            await library.refreshProgress()
        }

        /// One finished download with a file, a cover drawn into the cache, and a position.
        private func fill(_ library: MacLibrary) async throws {
            let store = DownloadStore()
            try store.prepare()
            let file = store.location(for: "storage-walk", mediaType: "application/vnd.comicbook+zip", title: "Walk")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(repeating: 7, count: 300_000).write(to: file)
            let remote = try #require(URL(string: "http://127.0.0.1/storage-walk.cbz"))
            library.downloads.queue.record(Download(
                id: "storage-walk", title: "Walk", remote: remote, mediaType: "application/vnd.comicbook+zip",
                state: .finished, expectedBytes: 300_000, downloadedBytes: 300_000, completedAt: Date()
            ))
            let publication = try #require(Walk.publication(named: "natural-sort", in: library))
            _ = await library.model.cover(for: publication, maxPixelSize: 300)
            let progress = try #require(library.progress)
            try await progress.save(ReadingProgress(
                identity: publication.identity, position: .page(index: 2, of: 12), updatedAt: Date()
            ))
        }
    }
}
