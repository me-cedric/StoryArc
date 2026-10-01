import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// Global pause, resume and cancel, sent to the one app-level queue.
///
/// `offline-downloads`' second requirement asks for "per-item and global pause, resume,
/// cancel" together. `DownloadQueue.pause` and `.resume` already existed with no caller
/// from the Downloads destination, and nothing offered the global three at all —
/// `DownloadQueueSection.swift` drew reorder and Stop only. Android asserts the same three
/// claims in `DownloadQueueTest`.
@Suite("Global pause, resume and cancel")
@MainActor
struct DownloadQueueGlobalControlsTests {

    /// A store of its own, in a fresh defaults suite and an empty directory, already
    /// holding the given records.
    ///
    /// None of them are `.queued`: `pump()` runs once at `init` and would start one before
    /// this suite ever calls anything, leaving a test unable to tell its own write from the
    /// queue's.
    private func store(holding downloads: [Download]) throws -> DownloadStore {
        let name = "download-global-controls-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)
        store.save(DownloadLibrary(downloads: downloads))
        return store
    }

    private func download(
        id: String,
        state: Download.State
    ) -> Download {
        Download(
            id: id,
            title: "Harbour Lights \(id)",
            remote: URL(string: "https://example.invalid/\(id).epub") ?? URL(fileURLWithPath: "/\(id).epub"),
            mediaType: "application/epub+zip",
            state: state
        )
    }

    @Test("Pausing every download pauses only what was queued or running")
    func pauseAllPausesWhatCanBePaused() throws {
        let queue = DownloadQueue(
            store: try store(holding: [
                download(id: "running", state: .running),
                download(id: "paused", state: .paused(.byReader)),
                download(id: "finished", state: .finished),
            ]),
            settings: { AppSettings() }
        )

        queue.pauseAll()

        #expect(queue.library["running"]?.state == .paused(.byReader))
        #expect(queue.library["paused"]?.state == .paused(.byReader))
        #expect(queue.library["finished"]?.state == .finished, "A finished download was touched.")
    }

    @Test("Resuming every download puts what was paused or failed back in the queue, and nothing else")
    func resumeAllQueuesWhatWasHeld() throws {
        let queue = DownloadQueue(
            store: try store(holding: [
                download(id: "paused", state: .paused(.waitingForWiFi)),
                download(id: "failed", state: .failed(reason: "it stopped", attempts: 3)),
                download(id: "finished", state: .finished),
            ]),
            settings: { AppSettings() }
        )

        queue.resumeAll()

        // Both leave `.paused`/`.failed`; `pump()` takes the concurrency-careful default and
        // starts the first it finds room for, which is "queued" with the bound met either
        // way — the claim this test pins is that neither is left exactly where it was.
        #expect(queue.library["paused"]?.state == .running || queue.library["paused"]?.state == .queued)
        #expect(queue.library["failed"]?.state == .running || queue.library["failed"]?.state == .queued)
        #expect(queue.library["finished"]?.state == .finished, "A finished download was touched.")
    }

    @Test("Cancelling every download removes everything still pending, and keeps what finished")
    func cancelAllRemovesEverythingPending() throws {
        let queue = DownloadQueue(
            store: try store(holding: [
                download(id: "running", state: .running),
                download(id: "paused", state: .paused(.byReader)),
                download(id: "failed", state: .failed(reason: "it stopped", attempts: 3)),
                download(id: "finished", state: .finished),
            ]),
            settings: { AppSettings() }
        )

        queue.cancelAll()

        #expect(queue.library["running"] == nil)
        #expect(queue.library["paused"] == nil)
        #expect(queue.library["failed"] == nil)
        #expect(queue.library["finished"]?.state == .finished, "A finished download was removed.")
    }
}
