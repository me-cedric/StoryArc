import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// Removing a finished publication's download, reversibly.
///
/// `offline-downloads`: the download is removed, "its progress is kept, and the removal is
/// undoable for 10 seconds". Undoable is the part worth testing: a file already deleted can
/// only be put back by downloading it again, which is not an undo.
@Suite("Removing a finished download", .serialized)
struct FinishedCleanupTests {
    private func store(_ name: String) -> DownloadStore {
        let directory = URL.temporaryDirectory.appending(path: "storyarc-cleanup-\(name)")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DownloadStore(
            defaults: UserDefaults(suiteName: "cleanup-\(name)") ?? .standard,
            directory: directory
        )
    }

    private func libraryWith(_ store: DownloadStore, id: String) -> DownloadLibrary {
        let download = Download(
            id: id,
            title: id,
            remote: URL(fileURLWithPath: "/fixtures").appending(path: id),
            mediaType: "application/vnd.comicbook+zip",
            state: .finished,
            downloadedBytes: 3
        )
        let file = store.location(of: download)
        // The id is a directory now, so the fixture has to make it like the queue does.
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data([1, 2, 3]).write(to: file)
        return DownloadLibrary(downloads: [download])
    }

    @Test("finds the download whose file the reader finished")
    func finds() {
        let store = store("finds")
        let library = libraryWith(store, id: "one")
        let found = store.finishedDownload(in: library) { $0.hasSuffix("one.cbz") }
        #expect(found?.id == "one")
    }

    @Test("finds nothing when the reader has finished nothing")
    func findsNothing() {
        let store = store("nothing")
        #expect(store.finishedDownload(in: libraryWith(store, id: "one")) { _ in false } == nil)
    }

    @Test("the bytes wait rather than going, so the removal can be undone")
    func undoable() throws {
        let store = store("undo")
        let library = libraryWith(store, id: "one")
        let home = store.location(for: "one", mediaType: "application/vnd.comicbook+zip", title: "one")

        let outcome = store.removeAfterFinishing("one", from: library)
        let removed = try #require(outcome)
        #expect(removed.library["one"] == nil)
        #expect(!FileManager.default.fileExists(atPath: home.path), "the file is out of the way")
        #expect(FileManager.default.fileExists(atPath: removed.removed.aside.path),
                "but it has not been deleted")

        let restored = removed.removed.undo(removed.library, in: store)
        #expect(restored["one"]?.id == "one")
        #expect(FileManager.default.fileExists(atPath: home.path), "and it is back where it was")
    }

    @Test("settling lets the bytes go")
    func settles() throws {
        let store = store("settle")
        let library = libraryWith(store, id: "one")
        let removed = try #require(store.removeAfterFinishing("one", from: library))
        removed.removed.settle()
        #expect(!FileManager.default.fileExists(atPath: removed.removed.aside.path))
    }

    @Test("a download with no file on disk is left alone")
    func missingFile() {
        let store = store("missing")
        let library = libraryWith(store, id: "one")
        try? FileManager.default.removeItem(
            at: store.location(for: "one", mediaType: "application/vnd.comicbook+zip", title: "one")
        )
        #expect(store.removeAfterFinishing("one", from: library) == nil)
    }
}
