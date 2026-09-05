import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A failed download retried from the Downloads screen has to start moving, not just say so.
///
/// That screen writes the download store and owns no `DownloadQueue`: the only queue the app
/// builds is `@State` on a catalogue page. So *Retry* there can mark the record `queued` and
/// has nowhere to send the pump — and `DownloadQueue.reconsider()`, the method written for
/// exactly that, had no callers on either platform. A button that turned a red row into a
/// queued one that nothing would ever run is the control that lies, and this suite is what
/// keeps it from being one. Two ends:
///
/// - **No queue alive.** The screen's write stands, and the next queue built reads it in its
///   `init` and starts it — the same line that puts back a transfer the app died during.
/// - **A queue alive.** `DownloadQueue.retry(_:)` reaches it, and the transfer starts now.
///
/// These are the first host tests to build a `DownloadQueue` at all. Nothing here waits on
/// the transfer, which goes to an address that resolves to nothing: the claim is that the
/// record reaches `running`, which `start` marks before the transfer's task gets a turn, and
/// both the queue and the test are on the main actor, so the assertion reads it first.
@Suite("Retrying a failed download")
@MainActor
struct DownloadQueueRetryTests {

    /// The reason the September sweep's injected record carries, three attempts in.
    private static let failed = Download.State.failed(
        reason: "The server did not answer in time.",
        attempts: 3
    )

    /// A store of its own, in a fresh defaults suite and an empty directory, holding one
    /// record in the given state. Ids differ per test because the registry `retry` asks is
    /// shared by every queue alive in this process, and a queue from another test still
    /// holding the same id as failed would answer for it.
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

    /// **No queue alive.** What `DownloadsDestination.retry` writes when nothing takes the
    /// retry is a record marked `queued`; the next queue built over that store starts it.
    @Test("A record put back in the queue is picked up when a queue is next built")
    func pickedUp() throws {
        let id = "picked-up-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)

        // The screen's own write, and the answer it gets with no queue to hand it to.
        store.save(store.library().marking(id, as: .queued))
        #expect(DownloadQueue.retry(id) == false)

        let queue = queue(over: store)
        #expect(queue.library[id]?.state == .running)
    }

    /// **A queue alive.** The one built on a catalogue page, still holding the record as
    /// failed while the reader is on the Downloads tab, is told, resumes it and pumps.
    @Test("A live queue takes the retry and starts the transfer")
    func liveQueue() throws {
        let id = "live-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)
        let queue = queue(over: store)
        // Building the queue changed nothing: a failed record is not what the pump starts.
        #expect(queue.library[id]?.state == Self.failed)

        #expect(DownloadQueue.retry(id) == true)

        #expect(queue.library[id]?.state == .running)
        // And the record the Downloads screen reads no longer says failed. `running` is
        // written as `queued` on purpose — see `StoredDownload` — so this is the stored word.
        #expect(store.library()[id]?.state == .queued)
    }

    /// The registry is asked by id, and a queue that holds a different record is not the one.
    @Test("A queue that does not hold the record does not answer for it")
    func someoneElse() throws {
        let id = "other-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)
        let queue = queue(over: store)

        #expect(DownloadQueue.retry("not-\(id)") == false)
        #expect(queue.library[id]?.state == Self.failed)
    }

    /// Failed only. A row paused for Wi-Fi keeps *Stop*, not *Retry*, and a retry that
    /// somehow named it would re-queue it only to have it pause again on the next pump.
    ///
    /// Paused through the queue rather than through the store, because the store cannot hold
    /// a pause: `StoredDownload` writes one as `queued`, since a pause is a fact about a live
    /// queue and a record read back at launch has no queue to be paused in.
    @Test("A paused download is not what this retries")
    func paused() throws {
        let id = "paused-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)
        let queue = queue(over: store)
        queue.library = queue.library.marking(id, as: .paused(.waitingForWiFi))

        #expect(DownloadQueue.retry(id) == false)
        #expect(queue.library[id]?.state == .paused(.waitingForWiFi))
    }

    /// Two catalogue pages alive at once — a split view, a page kept in a navigation stack —
    /// both read the store and both hold the record as failed. One tap is one transfer: the
    /// first queue takes it and the second is left as it was, rather than both starting the
    /// same bytes and one continuation never being resumed.
    @Test("Two live queues holding the same failed record start one transfer, not two")
    func twoLiveQueues() throws {
        let id = "twice-\(UUID().uuidString)"
        let store = try store(holding: Self.failed, id: id)
        let first = queue(over: store)
        let second = queue(over: store)

        #expect(DownloadQueue.retry(id) == true)

        let running = [first, second].filter { $0.library[id]?.state == .running }
        #expect(running.count == 1)
    }
}
