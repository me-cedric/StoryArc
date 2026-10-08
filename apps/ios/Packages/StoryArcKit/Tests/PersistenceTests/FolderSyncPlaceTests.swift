import Foundation
import Testing

@testable import Persistence

/// `library-sync` task 2.3: the sync document in a picked folder, held across a relaunch by the
/// same security-scoped bookmark `local-library` keeps. A real temporary directory and a private
/// `UserDefaults` suite, as `FolderBookmarksTests` uses.
@Suite("Folder sync place")
struct FolderSyncPlaceTests {
    private let name = "StoryArc Library.json"

    private func temporaryFolder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)"))
    }

    @Test("A picked folder takes a write, gives it back, and takes an overwrite at that version")
    func writesReadsAndOverwrites() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let place = FolderSyncPlace(folder: folder)

        #expect(try await place.read(name) == nil)
        #expect(try await place.write(name, data: Data("one".utf8), replacing: nil))
        let first = try #require(try await place.read(name))
        #expect(first.data == Data("one".utf8))
        #expect(try await place.names() == [name])

        #expect(try await place.write(name, data: Data("two, longer".utf8), replacing: first.version))
        #expect(try Data(contentsOf: folder.appending(path: name)) == Data("two, longer".utf8))
    }

    @Test("A write against a version that changed writes nothing")
    func staleVersionWritesNothing() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let place = FolderSyncPlace(folder: folder)

        #expect(try await place.write(name, data: Data("first".utf8), replacing: nil))
        #expect(try await !place.write(name, data: Data("second".utf8), replacing: nil))
        #expect(try await !place.write(name, data: Data("second".utf8), replacing: "not-the-version"))
        #expect(try await place.read(name)?.data == Data("first".utf8))
        #expect(try await place.delete(name))
        #expect(try await place.read(name) == nil)
    }

    @Test("The chosen folder is the same place after a relaunch")
    func folderSurvivesARelaunch() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try defaults()
        try SyncPlaceStore(defaults: defaults).chooseFolder(folder)
        _ = try await FolderSyncPlace(folder: folder).write(name, data: Data("kept".utf8), replacing: nil)

        // A new store over the same defaults is what a relaunch is.
        let relaunched = SyncPlaceStore(defaults: defaults)
        #expect(relaunched.choice() == .folder(name: folder.lastPathComponent))
        let restored = try #require(relaunched.folder())
        #expect(try await FolderSyncPlace(folder: restored).read(name)?.data == Data("kept".utf8))
        // The library's own folders do not hold it.
        #expect(FolderBookmarks(defaults: defaults).restore().folders.isEmpty)
    }

    @Test("A removed folder throws rather than reading as empty")
    func removedFolderThrows() async throws {
        let folder = try temporaryFolder()
        let place = FolderSyncPlace(folder: folder)
        try FileManager.default.removeItem(at: folder)

        await #expect(throws: (any Error).self) { _ = try await place.read(name) }
        await #expect(throws: (any Error).self) { _ = try await place.write(name, data: Data(), replacing: nil) }
    }

    @Test("Turning sync off forgets the place")
    func turningOffForgets() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try defaults()
        let store = SyncPlaceStore(defaults: defaults)
        try store.chooseFolder(folder)
        store.turnOff()

        #expect(SyncPlaceStore(defaults: defaults).choice() == nil)
        #expect(SyncPlaceStore(defaults: defaults).folder() == nil)
    }
}
