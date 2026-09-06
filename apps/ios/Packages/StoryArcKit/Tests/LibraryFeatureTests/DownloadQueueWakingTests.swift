import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A held queue has to start again by itself, without the reader going back to the screen.
///
/// `offline-downloads` promises that a download paused for Wi-Fi "resumes automatically when
/// [Wi-Fi] returns". `DownloadQueue.reconsider()` was written for that promise and had no
/// caller on either platform, so the promise was kept only by accident: a reader who queued
/// a download on cellular, then walked into Wi-Fi range, found a queue that stayed stopped
/// until something else happened to pump it.
///
/// Three claims, one per caller this suite gave `reconsider()`:
///
/// - **The network changed.** `NetworkCost` reports the new connection, and the queue starts
///   its pending transfer with nothing else called.
/// - **The same notice, several times.** A path update fires repeatedly as an interface
///   comes up, and starting one transfer twice would be worse than the defect being fixed.
/// - **Room was freed.** Removing a finished download drops `bytesOnDisk` below the reader's
///   limit, and the queue that was held by it starts.
///
/// And a fourth about lifetime: the observer holds the queue weakly, so the queue is free to
/// die with the page that made it.
///
/// Nothing here waits on a transfer, which goes to an address that resolves to nothing. The
/// claim is that the record reaches `running`, which `start` marks before the transfer's
/// task gets a turn, and both the queue and the test are on the main actor, so the assertion
/// reads it first. `DownloadQueueRetryTests` makes the same argument.
@Suite("Waking a held download queue")
@MainActor
struct DownloadQueueWakingTests {

    /// A store of its own, in a fresh defaults suite and an empty directory.
    ///
    /// Ids differ per test because `DownloadQueue.retry(_:)` asks a registry shared by every
    /// queue alive in this process, and a queue from another test holding the same id would
    /// answer for it.
    private func store(holding downloads: [Download]) throws -> DownloadStore {
        let name = "download-waking-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)
        store.save(DownloadLibrary(downloads: downloads))
        return store
    }

    private func queued(id: String) -> Download {
        Download(
            id: id,
            title: "Harbour Lights 04",
            remote: URL(string: "https://example.invalid/hl04.epub")!,
            mediaType: "application/epub+zip",
            state: .queued,
            expectedBytes: 8_400_000
        )
    }

    private func finished(id: String, bytes: Int64) -> Download {
        Download(
            id: id,
            title: "Harbour Lights 01",
            remote: URL(string: "https://example.invalid/hl01.epub")!,
            mediaType: "application/epub+zip",
            state: .finished,
            expectedBytes: bytes,
            downloadedBytes: bytes
        )
    }

    /// **The network changed.** Wi-Fi-only is on and the monitor has not answered, so the
    /// queue reads the link as cellular and holds. The only call after that is the report of
    /// the new connection.
    @Test("A queue waiting for Wi-Fi starts its transfer when Wi-Fi returns")
    func wifiReturns() throws {
        let id = "wifi-returns-\(UUID().uuidString)"
        let store = try store(holding: [queued(id: id)])
        let queue = DownloadQueue(
            store: store,
            settings: { AppSettings(downloadOverWifiOnly: true) }
        )

        #expect(queue.held == .waitingForWifi)
        #expect(queue.library[id]?.state == .queued)

        queue.network.note(careful: false, cellular: false)

        #expect(queue.held == nil)
        #expect(queue.library[id]?.state == .running)
    }

    /// **The same notice, several times.** `NWPathMonitor` reports an interface coming up
    /// more than once, and `pump` is what makes that safe: `start` marks the record running
    /// before it returns, so the next pump no longer sees it queued.
    @Test("Repeated network notices do not start the same download twice")
    func noDoubleStart() throws {
        let id = "no-double-start-\(UUID().uuidString)"
        let store = try store(holding: [queued(id: id)])
        let queue = DownloadQueue(
            store: store,
            settings: { AppSettings(downloadOverWifiOnly: true) }
        )

        for _ in 0..<5 { queue.network.note(careful: false, cellular: false) }

        #expect(queue.running.count == 1)
        #expect(queue.library.downloads.filter { $0.state == .running }.count == 1)
    }

    /// **Room was freed.** The reader's own limit is reached, so the queue is held; deleting
    /// a finished publication is the remedy the requirement names, and it has to be enough
    /// on its own.
    @Test("A queue held by the storage limit starts when room is freed")
    func roomFreed() throws {
        let kept = "kept-\(UUID().uuidString)"
        let wanted = "wanted-\(UUID().uuidString)"
        let store = try store(holding: [
            finished(id: kept, bytes: 2_000_000_000),
            queued(id: wanted),
        ])
        let queue = DownloadQueue(
            store: store,
            settings: { AppSettings(maximumDownloadBytes: 1_000_000_000) }
        )

        #expect(queue.held == .storageFull)
        #expect(queue.library[wanted]?.state == .queued)

        queue.remove(kept)

        #expect(queue.held == nil)
        #expect(queue.library[wanted]?.state == .running)
    }

    /// **Lifetime.** The queue installs the observer on a `NetworkCost` it owns. A strong
    /// capture there would make a cycle, and a catalogue page's queue would outlive the page
    /// for ever — along with its client and its credential closure.
    ///
    /// An empty store, so no transfer is started and nothing holds the queue but the
    /// observer under test. The wait is for `reclaim`, which the initialiser starts and
    /// which holds the queue until it answers.
    @Test("The queue does not keep itself alive through the network observer")
    func observerHoldsTheQueueWeakly() async throws {
        let store = try store(holding: [])
        weak var cost: NetworkCost?
        do {
            let queue = DownloadQueue(store: store, settings: { AppSettings() })
            cost = queue.network
            #expect(cost != nil)
        }

        for _ in 0..<200 where cost != nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(cost == nil, "The network observer is holding the queue alive.")
    }
}
