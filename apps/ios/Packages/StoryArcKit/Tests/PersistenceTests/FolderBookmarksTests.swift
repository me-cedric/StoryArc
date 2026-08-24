import Foundation
import Testing

@testable import Persistence

/// `local-library` requires a picked folder to survive a restart. These use a real
/// temporary directory and a private `UserDefaults` suite, because a bookmark that
/// only works against a mock is not evidence of anything.
@Suite("Folder bookmarks")
struct FolderBookmarksTests {
    private func fresh() -> (FolderBookmarks, UserDefaults, String) {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (FolderBookmarks(defaults: defaults), defaults, name)
    }

    private func temporaryFolder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "bm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A folder added comes back on the next launch")
    func roundTrip() throws {
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try bookmarks.add(folder)

        // A *new* instance, which is what a relaunch actually is.
        let restored = FolderBookmarks(defaults: defaults).restore()
        #expect(restored.folders.count == 1)
        #expect(restored.folders.first?.lastPathComponent == folder.lastPathComponent)
        #expect(restored.stale.isEmpty)
    }

    @Test("Nothing added restores nothing, rather than failing")
    func empty() {
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let restored = bookmarks.restore()
        #expect(restored.folders.isEmpty)
        #expect(restored.stale.isEmpty)
    }

    @Test("Adding the same folder twice keeps one entry")
    func noDuplicates() throws {
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try bookmarks.add(folder)
        try bookmarks.add(folder)
        #expect(bookmarks.restore().folders.count == 1)
    }

    @Test("Several folders are all remembered, in the order they were added")
    func multiple() throws {
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try temporaryFolder()
        let second = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        try bookmarks.add(first)
        try bookmarks.add(second)
        let restored = bookmarks.restore()
        #expect(restored.folders.count == 2)
        #expect(restored.folders.first?.lastPathComponent == first.lastPathComponent)
    }

    @Test("A folder that has gone is reported by name, not silently dropped")
    func staleIsNamed() throws {
        // `local-library`: the explanation names the folder, because "a folder is no
        // longer available" sends someone hunting through four of them.
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try temporaryFolder()
        let name = folder.lastPathComponent

        try bookmarks.add(folder)
        try FileManager.default.removeItem(at: folder)

        let restored = bookmarks.restore()
        #expect(restored.folders.isEmpty)
        #expect(restored.stale.map(\.name) == [name])
    }

    @Test("A folder that has gone is not reported for ever")
    func staleIsDroppedAfterReporting() throws {
        // Told once. A notice that returns every launch for a folder deleted months
        // ago is noise the user cannot act on.
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try temporaryFolder()

        try bookmarks.add(folder)
        try FileManager.default.removeItem(at: folder)

        #expect(bookmarks.restore().stale.count == 1)
        #expect(bookmarks.restore().stale.isEmpty)
    }

    @Test("Forgetting a folder removes it")
    func remove() throws {
        let (bookmarks, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try bookmarks.add(folder)
        bookmarks.remove(named: folder.lastPathComponent)
        #expect(bookmarks.restore().folders.isEmpty)
    }

    @Test("One library's folders do not leak into another's defaults")
    func isolated() throws {
        let (first, firstDefaults, firstSuite) = fresh()
        let (second, secondDefaults, secondSuite) = fresh()
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try first.add(folder)
        #expect(second.restore().folders.isEmpty)
    }
}
