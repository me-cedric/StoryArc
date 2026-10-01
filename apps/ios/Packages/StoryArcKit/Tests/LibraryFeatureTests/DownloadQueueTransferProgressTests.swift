import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A transfer's row has two things to say while it runs, and the queue used to write
/// neither of them: the size the feed stated, and how far the bytes written so far get it.
///
/// `offline-downloads`' *Progress never moves during a transfer, and the feed's stated size
/// is never used*. `DownloadQueueProgressTests` pins what a row says once both are known;
/// this pins how the queue comes to know them. Android asserts the same two claims in
/// `DownloadQueueEnqueueTest` and `DownloadQueueTest`.
@Suite("A transfer's size and progress reach the queue")
@MainActor
struct DownloadQueueTransferProgressTests {

    private func store() throws -> DownloadStore {
        let name = "download-transfer-progress-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadStore(defaults: defaults, directory: directory)
    }

    @Test("A download enqueued with a stated size records it before any byte arrives")
    func enqueueRecordsTheStatedSize() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/hl09.epub")!,
            mediaType: "application/epub+zip",
            kind: .open,
            length: 41_000_000
        )

        queue.enqueue(OpdsEntry(id: "hl09", title: "Harbour Lights 09"), using: acquisition)

        #expect(queue.library[queue.downloadID(for: "hl09")]?.expectedBytes == 41_000_000)
    }

    @Test("A feed that states no size leaves the row with none to fabricate")
    func enqueueWithNoStatedSizeRecordsNone() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/hl10.epub")!,
            mediaType: "application/epub+zip",
            kind: .open
        )

        queue.enqueue(OpdsEntry(id: "hl10", title: "Harbour Lights 10"), using: acquisition)

        #expect(queue.library[queue.downloadID(for: "hl10")]?.expectedBytes == nil)
    }

    @Test("Advancing a download in flight writes what has landed, not just what finished")
    func advanceWritesProgress() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/hl11.epub")!,
            mediaType: "application/epub+zip",
            kind: .open,
            length: 8_400_000
        )
        queue.enqueue(OpdsEntry(id: "hl11", title: "Harbour Lights 11"), using: acquisition)
        let id = queue.downloadID(for: "hl11")

        queue.advance(id, written: 3_100_000, expected: 8_400_000)

        #expect(queue.library[id]?.downloadedBytes == 3_100_000)
        #expect(queue.library[id]?.expectedBytes == 8_400_000)
    }

    @Test("A server that states no total through the transfer leaves the row with none")
    func advanceWithNoExpectedLeavesExpectedAlone() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/hl12.epub")!,
            mediaType: "application/epub+zip",
            kind: .open
        )
        queue.enqueue(OpdsEntry(id: "hl12", title: "Harbour Lights 12"), using: acquisition)
        let id = queue.downloadID(for: "hl12")

        // `URLSessionDownloadDelegate` reports `-1` for an unknown total, and `advance` is
        // where that is turned into the honest absence `DownloadLibrary/advancing` keeps.
        queue.advance(id, written: 1_200_000, expected: -1)

        #expect(queue.library[id]?.downloadedBytes == 1_200_000)
        #expect(queue.library[id]?.expectedBytes == nil)
    }

    @Test("A resume the system carried on is stated while the transfer runs")
    func noteAttemptRecordsAResume() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/hl13.epub")!,
            mediaType: "application/epub+zip",
            kind: .open
        )
        queue.enqueue(OpdsEntry(id: "hl13", title: "Harbour Lights 13"), using: acquisition)
        let id = queue.downloadID(for: "hl13")

        queue.noteAttempt(id, resumed: true)

        #expect(queue.library[id]?.lastAttempt == .resumed)
    }

    @Test("A resume the server refused is stated as a restart while the transfer runs")
    func noteAttemptRecordsARestart() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/hl14.epub")!,
            mediaType: "application/epub+zip",
            kind: .open
        )
        queue.enqueue(OpdsEntry(id: "hl14", title: "Harbour Lights 14"), using: acquisition)
        let id = queue.downloadID(for: "hl14")

        queue.noteAttempt(id, resumed: false)

        #expect(queue.library[id]?.lastAttempt == .restarted)
    }

    @Test("An attempt for a download the queue no longer holds writes nothing back")
    func noteAttemptOfAnUnknownDownloadDoesNothing() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })

        queue.noteAttempt("gone", resumed: true)

        #expect(queue.library["gone"] == nil)
    }

    @Test("Advancing a download the queue no longer holds does nothing")
    func advanceOfAnUnknownDownloadDoesNothing() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })

        queue.advance("gone", written: 1_000, expected: 2_000)

        #expect(queue.library["gone"] == nil)
    }
}
