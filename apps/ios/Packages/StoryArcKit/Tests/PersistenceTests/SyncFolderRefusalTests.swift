import Foundation
import Testing

@testable import Persistence

/// `library-sync` task 5.5: a library folder is never the sync place, so the sync document never
/// lands among the books. Android's `SyncFolderGrant` refuses a library folder the same way.
@Suite("A library folder is refused as the sync place")
struct SyncFolderRefusalTests {

    private func folder(in parent: URL = .temporaryDirectory, named name: String = UUID().uuidString) throws -> URL {
        let url = parent.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)"))
    }

    /// Picks `url` in a store whose Documents folder is `documents`, and says whether it was refused.
    private func refuses(_ url: URL, documents: URL, defaults: UserDefaults) -> Bool {
        let store = SyncPlaceStore(defaults: defaults, documents: documents)
        do {
            try store.chooseFolder(url)
        } catch SyncFolderRefusal.isLibrary {
            #expect(store.choice() == nil)
            return true
        } catch {
            Issue.record("unexpected \(error)")
        }
        return false
    }

    @Test("The app's own Documents folder, and a folder inside it, are refused")
    func documentsIsRefused() throws {
        let documents = try folder()
        defer { try? FileManager.default.removeItem(at: documents) }
        let inside = try folder(in: documents, named: "Comics")

        #expect(refuses(documents, documents: documents, defaults: try defaults()))
        #expect(refuses(inside, documents: documents, defaults: try defaults()))
    }

    @Test("The File Provider storage root that On My iPhone opens is refused")
    func storageRootIsRefused() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try folder(in: parent, named: SyncPlaceStore.storageRoot)

        #expect(refuses(root, documents: try folder(), defaults: try defaults()))
    }

    @Test("A folder the library reads is refused")
    func libraryFolderIsRefused() throws {
        let library = try folder()
        defer { try? FileManager.default.removeItem(at: library) }
        let defaults = try defaults()
        try FolderBookmarks(defaults: defaults).add(library)

        #expect(refuses(library, documents: try folder(), defaults: defaults))
    }

    @Test("Any other folder is taken")
    func otherFolderIsTaken() throws {
        let documents = try folder()
        let other = try folder()
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: other)
        }
        let defaults = try defaults()

        #expect(!refuses(other, documents: documents, defaults: defaults))
        #expect(SyncPlaceStore(defaults: defaults).choice() == .folder(name: other.lastPathComponent))
    }
}
