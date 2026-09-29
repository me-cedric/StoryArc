import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A failed download retried from the Downloads screen has to start moving, not just say so.
///
/// The screen's *Retry* is `DownloadQueue.resume(_:)` on the one app-level queue
/// (dl-core 1.1). Before that queue existed, the screen owned no queue: it marked the record
/// `queued` and handed the pump to whichever catalogue page's queue happened to be alive. Two
/// ends are held here:
///
/// - **A record left queued.** The queue picks it up when it is built — the same line that
///   puts back a transfer the app died during.
/// - **A retry.** `resume` puts the failed record back and the transfer starts now.
///
/// Nothing here waits on the transfer, which goes to an address that resolves to nothing: the
/// claim is that the record reaches `running`, which `start` marks before the transfer's task
/// gets a turn, and both the queue and the test are on the main actor, so the assertion reads
/// it first.
@Suite("Retrying a failed download")
@MainActor
struct DownloadQueueRetryTests {

    /// The reason the September sweep's injected record carries, three attempts in.
    private static let failed = Download.State.failed(
        reason: "The server did not answer in time.",
        attempts: 3
    )

    /// A store of its own, in a fresh defaults suite and an empty directory, holding one
    /// record in the given state.
    private func store(holding state: Download.State, id: String) throws -> DownloadStore {
        let name = "download-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)
        store.save(DownloadLibrary(downloads: [
            Download(
                id: id,
                title: "Harbour Lights 03",
                remote: URL(string: "https://example.invalid/hl03.epub")!,
                mediaType: "application/epub+zip",
                state: state,
                expectedBytes: 8_400_000,
                downloadedBytes: 190_000
            ),
        ]))
        return store
    }

    /// Wi-Fi-only off, stated. `NetworkCost.isCellular` is `true` until the path monitor has
    /// answered — it errs toward using less — and a queue asked under the default settings
    /// would read that as a metered link before the monitor's first callback. The setting is
    /// what makes the answer the reader's rather than the monitor's timing.
    private func queue(over store: DownloadStore) -> DownloadQueue {
        DownloadQueue(store: store, settings: { AppSettings(downloadOverWifiOnly: false) })
    }

    @Test("A record left in the queue is picked up when the queue is built")
    func pickedUp() throws {
        let id = "picked-up-\(UUID().uuidString)"
        let store = try store(holding: .queued, id: id)

        let queue = queue(over: store)

        #expect(queue.library[id]?.state == .running)
    }

    @Test("A retry resumes the failed download and starts the transfer")
    func retryStarts() throws {
        let id = "retry-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)
        let queue = queue(over: store)
        // Building the queue changed nothing: a failed record is not what the pump starts.
        #expect(queue.library[id]?.state == Self.failed)

        queue.resume(id)

        #expect(queue.library[id]?.state == .running)
        // And the record the Downloads screen reads no longer says failed. `running` is
        // written as `queued` on purpose — see `StoredDownload` — so this is the stored word.
        #expect(store.library()[id]?.state == .queued)
    }

    @Test("A retry of a download the queue does not hold changes nothing")
    func someoneElse() throws {
        let id = "other-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)
        let queue = queue(over: store)

        queue.resume("not-\(id)")

        #expect(queue.library[id]?.state == Self.failed)
        #expect(queue.library["not-\(id)"] == nil)
    }
}
