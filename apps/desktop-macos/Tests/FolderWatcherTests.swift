import Foundation
import Testing

@testable import StoryArc

/// Live folder watching, task 2.20: a burst of 2,000 files reaches the library in a few
/// batches, and the window is never blocked.
@Suite("Folder watcher")
struct FolderWatcherTests {
    @Test("Two thousand events in one burst close as one batch")
    func batcherCoalesces() {
        var batcher = EventBatcher()
        for _ in 0..<2000 { batcher.noteEvents(1) }

        #expect(batcher.pendingEvents == 2000)
        let closed = batcher.closeBatch()
        #expect(closed)
        #expect(batcher.batches == 1)
        #expect(batcher.pendingEvents == 0)
        let closedAgain = batcher.closeBatch()
        #expect(!closedAgain)
        #expect(batcher.batches == 1)
    }

    @Test("A file copied into a watched folder is seen inside ten seconds, and 2,000 arrive in batches")
    @MainActor
    func burstArrivesInBatches() async throws {
        let folder = URL.temporaryDirectory.appending(path: "watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = MacFolderWatcher()
        var batches = 0
        var seenAt: Date?
        watcher.watch([folder]) {
            batches += 1
            if seenAt == nil { seenAt = Date() }
        }
        try await Task.sleep(for: .milliseconds(300))

        // The copy runs off the main actor; the main actor answers a hop while it runs, which
        // is what "the window stays responsive" measures here.
        let started = Date()
        let copy = Task.detached {
            for index in 0..<2000 {
                try? Data("page \(index)".utf8).write(to: folder.appending(path: "file-\(index).cbz"))
            }
        }
        var longestHop: TimeInterval = 0
        while !copy.isCancelled, Date().timeIntervalSince(started) < 2 {
            let before = Date()
            try await Task.sleep(for: .milliseconds(20))
            longestHop = max(longestHop, Date().timeIntervalSince(before) - 0.02)
        }
        _ = await copy.value
        // Polled with `await`, not with a run-loop spin: the stream's events arrive on the
        // main queue, and a synchronous spin inside this main-actor task would hold them back.
        let deadline = Date(timeIntervalSinceNow: 10)
        while batches == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        // One more quiet period, so a trailing batch is counted.
        try await Task.sleep(for: .milliseconds(1500))
        watcher.stop()

        let seen = try #require(seenAt)
        #expect(seen.timeIntervalSince(started) < 10)
        #expect(batches >= 1 && batches <= 10, "\(batches) batches for 2,000 files")
        #expect(longestHop < 0.25, "the main actor stalled for \(longestHop)s during the copy")
    }
}
