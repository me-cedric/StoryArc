import Foundation
import Testing

@testable import Persistence

/// `local-library` requires a picked folder to survive a restart. These use a real
/// temporary directory and a private `UserDefaults` suite, because a bookmark that
/// only works against a mock is not evidence of anything.
@Suite("Folder bookmarks")
struct FolderBookmarksTests {
    /// A private defaults suite, and the means to throw it away afterwards.
    private struct Suite {
        let bookmarks: FolderBookmarks
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Suite {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Suite(bookmarks: FolderBookmarks(defaults: defaults), defaults: defaults, name: name)
    }

    private func temporaryFolder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "bm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A folder added comes back on the next launch")
    func roundTrip() throws {
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try bookmarks.add(folder)

        // A *new* instance, which is what a relaunch actually is.
        let restored = FolderBookmarks(defaults: suite.defaults).restore()
        #expect(restored.folders.count == 1)
        #expect(restored.folders.first?.lastPathComponent == folder.lastPathComponent)
        #expect(restored.stale.isEmpty)
    }

    @Test("Nothing added restores nothing, rather than failing")
    func empty() throws {
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let restored = bookmarks.restore()
        #expect(restored.folders.isEmpty)
        #expect(restored.stale.isEmpty)
    }

    @Test("Adding the same folder twice keeps one entry")
    func noDuplicates() throws {
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try bookmarks.add(folder)
        try bookmarks.add(folder)
        #expect(bookmarks.restore().folders.count == 1)
    }

    @Test("Several folders are all remembered, in the order they were added")
    func multiple() throws {
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
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
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
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
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let folder = try temporaryFolder()

        try bookmarks.add(folder)
        try FileManager.default.removeItem(at: folder)

        #expect(bookmarks.restore().stale.count == 1)
        #expect(bookmarks.restore().stale.isEmpty)
    }

    @Test("Forgetting a folder removes it")
    func remove() throws {
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try bookmarks.add(folder)
        bookmarks.remove(named: folder.lastPathComponent)
        #expect(bookmarks.restore().folders.isEmpty)
    }

    // MARK: - Files

    private func temporaryFile() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "bm-\(UUID().uuidString).cbz")
        try Data("not really a comic".utf8).write(to: url)
        return url
    }

    @Test("A file the system handed over is not a folder library")
    func fileIsNotAFolder() throws {
        // The defect this test exists for: a handed-over file was stored here and came back
        // in `folders`, so the library registered a local-folder source named after the
        // comic and walked a regular file, which lists nothing. The reader got an empty
        // shelf named after their book.
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }

        try bookmarks.add(file)

        let restored = FolderBookmarks(defaults: suite.defaults).restore()
        #expect(restored.folders.isEmpty)
        #expect(restored.files.map(\.lastPathComponent) == [file.lastPathComponent])
        #expect(restored.stale.isEmpty)
    }

    @Test("A folder and a file are told apart in the same store")
    func foldersAndFilesCoexist() throws {
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let folder = try temporaryFolder()
        let file = try temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: file)
        }

        try bookmarks.add(folder)
        try bookmarks.add(file)

        let restored = bookmarks.restore()
        #expect(restored.folders.map(\.lastPathComponent) == [folder.lastPathComponent])
        #expect(restored.files.map(\.lastPathComponent) == [file.lastPathComponent])
    }

    @Test("A remembered file that has gone is forgotten, not reported as a folder")
    func staleFileIsNotAnUnavailableFolder() throws {
        // `local-library` reports an unavailable *folder* by name and offers to re-pick it.
        // A file another app handed over was never a library the reader configured, so
        // asking them to re-pick it as one would be asking for something that does not
        // exist. It is dropped instead.
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let file = try temporaryFile()

        try bookmarks.add(file)
        try FileManager.default.removeItem(at: file)

        let restored = bookmarks.restore()
        #expect(restored.stale.isEmpty)
        #expect(restored.files.isEmpty)
        #expect(bookmarks.restore().files.isEmpty)
    }

    @Test("Remembered files stop at a limit, oldest first, and folders are not counted")
    func rememberedFilesAreBounded() throws {
        // Nothing in the app asks a reader whether they meant to keep a file they opened
        // from a chat, and nothing offers to forget one. Unbounded, that is a shelf slowly
        // filling with other people's comics and an archive opened for each at every launch.
        let suite = try fresh()
        let bookmarks = suite.bookmarks
        defer { suite.discard() }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try bookmarks.add(folder)

        let files = try (0...FolderBookmarks.rememberedFileLimit).map { _ in try temporaryFile() }
        defer { for file in files { try? FileManager.default.removeItem(at: file) } }
        for file in files { try bookmarks.add(file) }

        let restored = bookmarks.restore()
        #expect(restored.files.count == FolderBookmarks.rememberedFileLimit)
        // The one that fell off is the one opened longest ago.
        let names = restored.files.map(\.lastPathComponent)
        #expect(!names.contains(files[0].lastPathComponent))
        #expect(names.contains(files[files.count - 1].lastPathComponent))
        // The library the reader picked is untouched by any of it.
        #expect(restored.folders.count == 1)
    }

    @Test("One library's folders do not leak into another's defaults")
    func isolated() throws {
        let firstSuite = try fresh()
        let first = firstSuite.bookmarks
        let secondSuite = try fresh()
        let second = secondSuite.bookmarks
        defer {
            firstSuite.discard()
            secondSuite.discard()
        }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try first.add(folder)
        #expect(second.restore().folders.isEmpty)
    }
}
