import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// One app-level queue is the only writer of the download store.
///
/// dl-core 1.1: a catalogue page built its own `DownloadQueue`, so two pages open over the
/// same store — or a page and a screen with no queue of its own, writing `DownloadStore`
/// directly — each held a different in-memory copy of the same records. Whichever saved
/// last won, which is what let a Kavita keep or a source removal be undone the next time any
/// catalogue's queue pumped. `DownloadQueueSourceKeyingTests` named this suite as the one that
/// owns it: "two catalogue queues writing one shared store without clobbering each other is
/// dl-core 1.1, not this task."
///
/// Every test resets `DownloadQueue`'s shared instance first, because it is process-wide
/// state and `swift test` can run this suite's cases beside `DownloadQueueRetryTests`'.
@Suite("The shared download queue is the only writer")
@MainActor
struct DownloadQueueSharedTests {

    private func store() throws -> DownloadStore {
        let name = "download-shared-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadStore(defaults: defaults, directory: directory)
    }

    private func acquisition(_ name: String) throws -> OpdsAcquisition {
        let href = try #require(URL(string: "https://example.invalid/\(name).epub"))
        return OpdsAcquisition(href: href, mediaType: "application/epub+zip", kind: .open)
    }

    @Test("Two catalogue pages asking for the shared queue get the same instance")
    func oneInstance() throws {
        DownloadQueue.resetShared()
        defer { DownloadQueue.resetShared() }
        let shared = try store()

        let page1 = DownloadQueue.shared(store: shared, settings: { AppSettings() })
        let page2 = DownloadQueue.shared(store: shared, settings: { AppSettings() })

        #expect(page1 === page2)
    }

    @Test("A download enqueued from one page's call is visible to another page's own call")
    func twoPagesShareOneCache() throws {
        DownloadQueue.resetShared()
        defer { DownloadQueue.resetShared() }
        let shared = try store()
        let sourceA = UUID()
        let sourceB = UUID()

        // Two catalogue pages, each asking for "the" queue the way `CatalogueBrowserView`
        // does, and each enqueuing an entry the *other* page's catalogue happens to number
        // the same way.
        let page1 = DownloadQueue.shared(store: shared, settings: { AppSettings() })
        page1.enqueue(OpdsEntry(id: "entry-1", title: "From A"), using: try acquisition("a"), sourceID: sourceA)

        let page2 = DownloadQueue.shared(store: shared, settings: { AppSettings() })
        page2.enqueue(OpdsEntry(id: "entry-1", title: "From B"), using: try acquisition("b"), sourceID: sourceB)

        // Both records exist, distinctly, because they are the same queue — and neither
        // page's enqueue overwrote the other's the way two separate in-memory copies would.
        #expect(page1.library[page1.downloadID(for: "entry-1", sourceID: sourceA)]?.title == "From A")
        #expect(page1.library[page1.downloadID(for: "entry-1", sourceID: sourceB)]?.title == "From B")
        #expect(page1.library.downloads.count == 2)
    }

    @Test("A record written through the queue survives an unrelated enqueue afterwards")
    func recordSurvivesALaterWrite() throws {
        DownloadQueue.resetShared()
        defer { DownloadQueue.resetShared() }
        let shared = try store()
        let queue = DownloadQueue.shared(store: shared, settings: { AppSettings() })

        // A Kavita keep, or a local import — a completed download `record(_:)` files without
        // this queue's own transfer having run it.
        let kept = Download(
            id: "kavita:server-1:9",
            sourceID: UUID(),
            title: "Kept chapter",
            remote: URL(string: "https://kavita.invalid/chapter/9")!,
            mediaType: "application/vnd.comicbook+zip",
            state: .finished,
            expectedBytes: 4_000,
            downloadedBytes: 4_000
        )
        queue.record(kept)

        // The write this queue would make for something unrelated — an ordinary enqueue,
        // which saves the queue's own cached `library` to the store. Before this queue was
        // the only writer, a second in-memory copy making this same save would have written
        // the kept chapter straight back out of existence.
        queue.enqueue(OpdsEntry(id: "entry-2", title: "Something else"), using: try acquisition("c"))

        #expect(queue.library[kept.id] != nil, "The queue's own later save overwrote the kept chapter.")
        #expect(shared.library()[kept.id] != nil, "The kept chapter did not survive on disk either.")
    }

    @Test("Removing a source's downloads through the queue leaves the other source's alone")
    func removingAllIsScopedToOneSource() throws {
        DownloadQueue.resetShared()
        defer { DownloadQueue.resetShared() }
        let shared = try store()
        let queue = DownloadQueue.shared(store: shared, settings: { AppSettings() })
        let gone = UUID()
        let kept = UUID()

        queue.enqueue(OpdsEntry(id: "entry-1", title: "Goes"), using: try acquisition("a"), sourceID: gone)
        queue.enqueue(OpdsEntry(id: "entry-1", title: "Stays"), using: try acquisition("b"), sourceID: kept)

        let removed = queue.removingAll(from: gone)

        #expect(removed.count == 1)
        #expect(queue.library[queue.downloadID(for: "entry-1", sourceID: gone)] == nil)
        #expect(queue.library[queue.downloadID(for: "entry-1", sourceID: kept)]?.title == "Stays")
        // The removal is the queue's own save, not a separate write a later pump could undo.
        #expect(shared.library().downloads.count == 1)
    }
}
