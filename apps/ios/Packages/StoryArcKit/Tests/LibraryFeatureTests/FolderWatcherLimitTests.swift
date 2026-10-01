import Foundation
import Testing

@testable import LibraryFeature

/// 10.9: past `FolderWatcher.limit` directories, a change is noticed only on the next return
/// to the foreground -- `reachedLimit` is what `WatchingFolders` polls on to ask again every
/// 10 seconds while the scene stays active instead.
@Suite("The folder watcher knows when it could not cover everything")
@MainActor
struct FolderWatcherLimitTests {
    /// A chain of `count` nested directories, one child each, so a breadth-first walk from
    /// the root finds exactly `count` directories including the root itself.
    private func chain(of count: Int) throws -> URL {
        var directory = URL.temporaryDirectory.appending(path: "watch-limit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory
        for level in 1..<count {
            directory = directory.appending(path: "level-\(level)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return root
    }

    @Test("A tree within the limit is covered in full")
    func withinLimit() throws {
        let root = try chain(of: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = FolderWatcher()
        defer { watcher.stop() }

        watcher.watch([root]) {}

        #expect(!watcher.reachedLimit)
    }

    @Test("A tree past the limit is not covered in full")
    func pastLimit() throws {
        let root = try chain(of: FolderWatcher.limit + 5)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = FolderWatcher()
        defer { watcher.stop() }

        watcher.watch([root]) {}

        #expect(watcher.reachedLimit)
    }
}
