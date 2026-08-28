import Foundation
import Testing

@testable import StoryArcCore

@Suite("Download library")
struct DownloadLibraryTests {
    /// A download of a publication that does not exist, which is all these tests need.
    private func download(_ id: String, source: UUID? = nil) -> Download {
        Download(
            id: id,
            sourceID: source,
            title: id,
            remote: URL(fileURLWithPath: "/\(id).epub"),
            mediaType: "application/epub+zip"
        )
    }

    @Test("A publication already known is not queued twice")
    func queueingIsIdempotent() {
        // `offline-downloads`: when a publication is already downloaded "the app does not
        // re-fetch it". A second tap on a book being fetched is the common way to ask.
        let library = DownloadLibrary()
            .queueing(download("a"))
            .queueing(download("a"))
        #expect(library.downloads.count == 1)
    }

    @Test("Finishing stamps the time it finished")
    func finishingStamps() throws {
        let library = DownloadLibrary().queueing(download("a")).marking("a", as: .finished)
        let finished = try #require(library["a"])
        #expect(finished.state == .finished)
        #expect(finished.completedAt != nil)
    }

    @Test("Progress without a declared size has no fraction")
    func progressWithoutASize() throws {
        // A bar that never moves is worse than no bar. The server did not say how big this
        // is, and the app should not pretend otherwise.
        let library = DownloadLibrary().queueing(download("a")).advancing("a", downloaded: 4096)
        #expect(try #require(library["a"]).fraction == nil)
    }

    @Test("Progress with a declared size is a fraction of it")
    func progressWithASize() throws {
        let library = DownloadLibrary()
            .queueing(download("a"))
            .advancing("a", downloaded: 50, expected: 200)
        #expect(try #require(library["a"]).fraction == 0.25)
    }

    @Test("Progress past the declared size is still one")
    func progressCannotExceedOne() throws {
        // A server that under-reports its own `Content-Length` is a real thing, and a
        // progress bar at 140% is how a reader learns not to trust the app.
        let library = DownloadLibrary()
            .queueing(download("a"))
            .advancing("a", downloaded: 300, expected: 200)
        #expect(try #require(library["a"]).fraction == 1)
    }

    @Test("A failure counts, and the third one stops the retries")
    func failuresCount() throws {
        var library = DownloadLibrary().queueing(download("a"))
        for attempt in 1...2 {
            library = library.failing("a", reason: "timed out")
            let failed = try #require(library["a"])
            #expect(failed.state == .failed(reason: "timed out", attempts: attempt))
            #expect(DownloadLibrary.shouldRetry(failed))
        }
        library = library.failing("a", reason: "timed out")
        #expect(!DownloadLibrary.shouldRetry(try #require(library["a"])))
    }

    @Test("Backoff doubles")
    func backoffDoubles() {
        #expect(DownloadLibrary.backoff(afterAttempts: 1) == .seconds(2))
        #expect(DownloadLibrary.backoff(afterAttempts: 2) == .seconds(4))
        #expect(DownloadLibrary.backoff(afterAttempts: 3) == .seconds(8))
    }

    @Test("A drag downwards lands where it was dropped")
    func movingDown() {
        // The destination a drag reports is an index in the list *before* the move.
        let library = DownloadLibrary()
            .queueing(download("a"))
            .queueing(download("b"))
            .queueing(download("c"))
            .moving("a", to: 2)
        #expect(library.downloads.map(\.id) == ["b", "a", "c"])
    }

    @Test("A drag upwards lands where it was dropped")
    func movingUp() {
        let library = DownloadLibrary()
            .queueing(download("a"))
            .queueing(download("b"))
            .queueing(download("c"))
            .moving("c", to: 0)
        #expect(library.downloads.map(\.id) == ["c", "a", "b"])
    }

    @Test("Removing a source takes its downloads and names them")
    func removingASource() {
        // Named, because the caller has files to delete. A library that forgot them
        // silently would leave the bytes on disk with nothing pointing at them.
        let source = UUID()
        let other = UUID()
        let library = DownloadLibrary()
            .queueing(download("a", source: source))
            .queueing(download("b", source: other))
            .queueing(download("c", source: source))
        let (kept, removed) = library.removingAll(from: source)
        #expect(kept.downloads.map(\.id) == ["b"])
        #expect(removed.map(\.id) == ["a", "c"])
    }

    @Test("What is on disk counts only what finished")
    func bytesOnDisk() {
        let library = DownloadLibrary()
            .queueing(download("a"))
            .queueing(download("b"))
            .advancing("a", downloaded: 100)
            .marking("a", as: .finished)
            .advancing("b", downloaded: 40)
        #expect(library.bytesOnDisk == 100)
        #expect(library.pending.map(\.id) == ["b"])
        #expect(library.finished.map(\.id) == ["a"])
    }
}
