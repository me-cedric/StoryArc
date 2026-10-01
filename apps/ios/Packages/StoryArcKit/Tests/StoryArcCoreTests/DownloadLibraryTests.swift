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

    @Test("A running download nobody is carrying goes back in the queue")
    func reclaimsTheStranded() {
        // A background transfer can finish with its caller gone, and the completion is
        // then delivered to nobody. Without this, the download waits for ever and keeps a
        // concurrency slot while it waits.
        let library = DownloadLibrary()
            .queueing(download("carried"))
            .queueing(download("stranded"))
            .marking("carried", as: .running)
            .marking("stranded", as: .running)
            .reclaiming(carriedBy: ["carried"])
        #expect(library["carried"]?.state == .running)
        #expect(library["stranded"]?.state == .queued)
    }

    @Test("Reclaiming leaves alone what is not running")
    func reclaimingSparesTheRest() {
        let library = DownloadLibrary()
            .queueing(download("done"))
            .queueing(download("waiting"))
            .marking("done", as: .finished)
            .reclaiming(carriedBy: [])
        #expect(library["done"]?.state == .finished)
        #expect(library["waiting"]?.state == .queued)
    }

    // MARK: - The storage view's breakdown

    /// A finished download of a given size, for the reason `download(_:source:)` is: the
    /// publication need not exist for these tests.
    private func finished(_ id: String, source: UUID? = nil, bytes: Int64) -> Download {
        Download(
            id: id,
            sourceID: source,
            title: id,
            remote: URL(fileURLWithPath: "/\(id).epub"),
            mediaType: "application/epub+zip",
            state: .finished,
            expectedBytes: bytes,
            downloadedBytes: bytes
        )
    }

    @Test("The largest download is first, and a queued one is not counted at all")
    func largestFirstOrdersByBytes() {
        let library = DownloadLibrary(downloads: [
            finished("small", bytes: 1_000),
            finished("large", bytes: 9_000),
            download("pending"),
        ])
        #expect(library.largestFirst.map(\.id) == ["large", "small"])
    }

    @Test("Bytes are summed per source, and nil keys a download with none")
    func bytesBySourceSumsPerSource() {
        let first = UUID()
        let second = UUID()
        let library = DownloadLibrary(downloads: [
            finished("a", source: first, bytes: 1_000),
            finished("b", source: first, bytes: 2_000),
            finished("c", source: second, bytes: 5_000),
            finished("d", bytes: 500),
        ])
        let totals = library.bytesBySource
        #expect(totals[first] == 3_000)
        #expect(totals[second] == 5_000)
        #expect(totals[nil] == 500)
    }

    @Test("A library with nothing finished has nothing to break down")
    func anEmptyLibraryBreaksDownToNothing() {
        let library = DownloadLibrary(downloads: [download("pending")])
        #expect(library.largestFirst.isEmpty)
        #expect(library.bytesBySource.isEmpty)
    }

    @Test("Recording an attempt writes it onto the download it belongs to, and no other")
    func recordingAttemptWritesOnlyItsOwnRecord() {
        let library = DownloadLibrary(downloads: [download("one"), download("two")])
            .recordingAttempt("one", as: .resumed)

        #expect(library["one"]?.lastAttempt == .resumed)
        #expect(library["two"]?.lastAttempt == nil)
    }

    @Test("Recording nil clears what an earlier attempt left")
    func recordingNilClearsTheAttempt() {
        let library = DownloadLibrary(downloads: [download("one")])
            .recordingAttempt("one", as: .restarted)
            .recordingAttempt("one", as: nil)

        #expect(library["one"]?.lastAttempt == nil)
    }
}

/// What a download's last attempt was, from whether there was something to resume and
/// what the server actually did with it.
///
/// `offline-downloads`' *Resuming after interruption* builds both outcomes and states
/// neither — `Download.LastAttempt.of` is the rule a row reads to tell them apart, lifted
/// out of `LibraryFeature/DownloadQueueTransfer` so a test can reach it without a real
/// transfer. Android answers the same three claims at `OpdsClient.download`'s own return
/// value, proved against a real server in `DownloadResumeTest`.
@Suite("What the last attempt at a download did")
struct DownloadLastAttemptTests {
    @Test("A first attempt, with nothing to carry on from, is neither a resume nor a restart")
    func firstAttemptIsNeither() {
        #expect(Download.LastAttempt.of(hadSomethingToResume: false, resumed: false) == nil)
        // Even a server that happens to answer 206 to a request that asked for nothing to
        // resume is not what this field means: there was nothing here to carry on.
        #expect(Download.LastAttempt.of(hadSomethingToResume: false, resumed: true) == nil)
    }

    @Test("Something to resume, honoured, is a resume")
    func honouredIsResumed() {
        #expect(Download.LastAttempt.of(hadSomethingToResume: true, resumed: true) == .resumed)
    }

    @Test("Something to resume, refused, is a restart")
    func refusedIsRestarted() {
        #expect(Download.LastAttempt.of(hadSomethingToResume: true, resumed: false) == .restarted)
    }
}
