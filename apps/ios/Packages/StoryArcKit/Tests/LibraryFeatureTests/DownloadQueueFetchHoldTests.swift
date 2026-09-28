import Foundation
import Testing

@testable import LibraryFeature
import Catalogue
import Persistence
import StoryArcCore

/// A reader who presses *Read* on a download that is failed or paused has to get a transfer,
/// not a continuation nothing is ever going to resume.
///
/// `fetch` enqueues before it waits, and `DownloadLibrary.queueing` is a no-op once a
/// publication's id is already known — that is right for a fresh tap on something already
/// queued or running, and wrong here: a failed download has no attempts left and a
/// reader-paused one stays paused until asked, so neither state resolves itself, and neither
/// one is what `pump` starts. Before the fix, `fetch` on either left the record exactly as it
/// was and waited for ever.
///
/// Nothing here awaits `fetch` itself — under the bug it would hang the test along with it.
/// The claim is only that the record reaches `running`, which `pump` writes before the
/// transfer's own task gets a turn, so one `Task.yield()` is enough to see it.
@Suite("Fetching a held or failed download")
@MainActor
struct DownloadQueueFetchHoldTests {
    private func store(holding state: Download.State, id: String) throws -> DownloadStore {
        let name = "download-fetch-hold-\(UUID().uuidString)"
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

    private func queue(over store: DownloadStore) -> DownloadQueue {
        DownloadQueue(store: store, settings: { AppSettings(downloadOverWifiOnly: false) })
    }

    private func acquisition(for id: String) -> (OpdsEntry, OpdsAcquisition) {
        (
            OpdsEntry(id: id, title: "Harbour Lights 03"),
            OpdsAcquisition(
                href: URL(string: "https://example.invalid/hl03.epub")!,
                mediaType: "application/epub+zip",
                kind: .open
            )
        )
    }

    @Test("A failed download is put back in the queue rather than waited on forever")
    func failedIsRequeued() async throws {
        let id = "fetch-failed-\(UUID().uuidString)"
        let store = try store(holding: .failed(reason: "The server did not answer in time.", attempts: 3), id: id)
        let queue = queue(over: store)
        #expect(queue.library[id]?.state.isFailed == true)

        let (entry, acquisition) = acquisition(for: id)
        Task { _ = await queue.fetch(entry, using: acquisition) }
        await Task.yield()
        await Task.yield()

        #expect(queue.library[id]?.state == .running)
    }

    @Test("A download the reader paused is put back in the queue rather than waited on forever")
    func readerPausedIsRequeued() async throws {
        let id = "fetch-paused-\(UUID().uuidString)"
        let store = try store(holding: .paused(.byReader), id: id)
        let queue = queue(over: store)
        #expect(queue.library[id]?.state == .paused(.byReader))

        let (entry, acquisition) = acquisition(for: id)
        Task { _ = await queue.fetch(entry, using: acquisition) }
        await Task.yield()
        await Task.yield()

        #expect(queue.library[id]?.state == .running)
    }

    // A Wi-Fi hold and a storage hold resolve by themselves — `pump`'s own
    // `holdForConnection`/`isAtLimit` checks run on every pump, `fetch`'s included — and are
    // covered there (`DownloadQueueConnectionTests`), not repeated here. A live `NWPathMonitor`
    // backs `NetworkCost` with no injection seam, so a Wi-Fi-hold variant of this test races
    // the real path callback and cannot be made to fail on demand; `failedIsRequeued` and
    // `readerPausedIsRequeued` above are what this fix actually changed.
}

private extension Download.State {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
