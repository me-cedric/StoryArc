import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What a launch puts back on the shelf.
///
/// `local-library` promises a picked folder is reachable "after a device restart without
/// asking again", and that a publication handed over by another app is remembered. Both
/// promises are kept by the same restore, and both were broken by the same two lines: the
/// hand-over stored a *file* among the folder libraries, and starting a scan cancelled the
/// one already running — so the second remembered place silently unmade the first.
///
/// Real folders, real bookmarks and the real corpus. A restore asserted against a mock
/// proves nothing about a bookmark, which is the part that fails on a device.
@Suite("Library restore")
@MainActor
struct LibraryRestoreTests {

    /// Walks up from this file to the committed fixture corpus.
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()

    /// A throwaway defaults suite, so one test's remembered places are not another's.
    private struct Store {
        let bookmarks: FolderBookmarks
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func store() throws -> Store {
        let name = "restore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Store(bookmarks: FolderBookmarks(defaults: defaults), defaults: defaults, name: name)
    }

    /// A folder holding one comic, copied out of the corpus.
    private func folder(holding fixture: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/\(fixture)"),
            to: root.appending(path: fixture)
        )
        return root
    }

    private func file(named fixture: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "handed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: fixture)
        try FileManager.default.copyItem(at: Self.corpus.appending(path: "comics/\(fixture)"), to: file)
        return file
    }

    /// Whether the shelf holds something that came out of this place.
    ///
    /// Compared on the resolved path: a URL that has been through a bookmark comes back as
    /// `/private/var/…` where the one handed in says `/var/…`, and they are the same place.
    private func holdsSomething(from place: URL, in model: LibraryModel) -> Bool {
        model.publications.contains {
            model.location(of: $0)?.resolvingSymlinksInPath().path
                .hasPrefix(place.resolvingSymlinksInPath().path) == true
        }
    }

    /// A model whose cached shelf is its own.
    ///
    /// The cache goes in the same stand-in directory for the reason that one exists: a walk
    /// writes a snapshot at its end, the default location is the machine's caches directory,
    /// and a restore is exactly what this suite drives — so a snapshot left by another test
    /// would be put on the shelf before the walk this test is about had begun.
    private func model(bookmarks: FolderBookmarks, documents: URL) -> LibraryModel {
        LibraryModel(bookmarks: bookmarks, documents: documents, cache: LibraryCache(directory: documents))
    }

    /// An empty directory standing in for the app's own Documents folder, so a restore in a
    /// test process never reaches the machine's real one.
    private func documents() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "documents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Every remembered folder is scanned, not only the last one")
    func everyFolderIsScanned() async throws {
        // The defect: `restoreFolders` started a scan per folder, and `scan` opened with
        // `scanTask?.cancel()`. Each folder cancelled the one before it, so a reader with
        // two libraries saw one — and the scan that was cancelled was the one they had
        // picked first.
        let store = try store()
        defer { store.discard() }
        let first = try folder(holding: "single-page.cbz")
        let second = try folder(holding: "natural-sort.cbz")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try store.bookmarks.add(first)
        try store.bookmarks.add(second)

        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }
        let model = self.model(bookmarks: store.bookmarks, documents: stand)
        model.restoreFolders()
        await model.scanTask?.value

        #expect(holdsSomething(from: first, in: model))
        #expect(holdsSomething(from: second, in: model))
    }

    @Test("A file handed over by another app comes back as a publication")
    func rememberedFileIsAPublication() async throws {
        // `local-library`: the app "offers, once and unobtrusively, to remember it in the
        // library". Remembered means the book is on the shelf on the next launch — not a
        // local-folder source named after the comic, holding nothing.
        let store = try store()
        defer { store.discard() }
        let handed = try file(named: "single-page.cbz")
        defer { try? FileManager.default.removeItem(at: handed.deletingLastPathComponent()) }
        try store.bookmarks.add(handed)

        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }
        let model = self.model(bookmarks: store.bookmarks, documents: stand)
        model.restoreFolders()
        await model.scanTask?.value

        #expect(holdsSomething(from: handed, in: model))
        #expect(model.folders.isEmpty)
        // No source at all, for the same reason the app's own Documents folder is not one:
        // there is nothing here for the reader to remove, rename or reconnect.
        #expect(!model.registry.sources.contains { $0.kind == .localFolder })
        #expect(model.unavailableFolders.isEmpty)
    }

    @Test("A remembered file inside a picked folder survives that folder's scan")
    func rememberedFileInsideAPickedFolder() async throws {
        // A reader can perfectly well open a comic from another app that also lives in a
        // folder they picked. The walk meets it a second time, keeps the row it already has
        // — the folder's source outranks no source at all — and then the reconcile asks
        // which publications this walk did not meet. A row put there before the walk was
        // never marked as met, so the book the reader had just opened was dropped from the
        // shelf the moment the scan finished.
        let store = try store()
        defer { store.discard() }
        let library = try folder(holding: "single-page.cbz")
        defer { try? FileManager.default.removeItem(at: library) }
        // A second comic, so the walk meets something it has not seen before: the reconcile
        // that drops what a walk missed only runs when the walk found anything at all.
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/natural-sort.cbz"),
            to: library.appending(path: "natural-sort.cbz")
        )
        let inside = library.appending(path: "single-page.cbz")
        try store.bookmarks.add(inside)
        try store.bookmarks.add(library)

        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }
        let model = self.model(bookmarks: store.bookmarks, documents: stand)
        model.restoreFolders()
        await model.scanTask?.value

        #expect(holdsSomething(from: inside, in: model))
    }

    @Test("A remembered file joins the folders rather than replacing them")
    func fileAndFoldersCoexist() async throws {
        let store = try store()
        defer { store.discard() }
        let library = try folder(holding: "natural-sort.cbz")
        let handed = try file(named: "single-page.cbz")
        defer {
            try? FileManager.default.removeItem(at: library)
            try? FileManager.default.removeItem(at: handed.deletingLastPathComponent())
        }
        try store.bookmarks.add(library)
        try store.bookmarks.add(handed)

        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }
        let model = self.model(bookmarks: store.bookmarks, documents: stand)
        model.restoreFolders()
        await model.scanTask?.value

        #expect(holdsSomething(from: library, in: model))
        #expect(holdsSomething(from: handed, in: model))
        // The library the reader picked is the only folder. A file that arrived through a
        // share sheet is not one, and listing it as one is what put an empty shelf named
        // after a comic in front of them.
        #expect(model.folders.count == 1)
        #expect(model.folders.first?.resolvingSymlinksInPath().path
            == library.resolvingSymlinksInPath().path)
    }
    /// A cached shelf whose files have moved does not double the library.
    ///
    /// **The regression this pins put every publication on the shelf twice**, photographed on
    /// 2026-09-05: once with its cover, and once as a format placeholder whose page read "This
    /// cannot be opened until it is on this device" for a file that was on the device. The
    /// snapshot records absolute paths; on iOS a path into the app's own container dies when
    /// the container's UUID changes on reinstall, while every file survives. The scan then
    /// re-finds the books at their new paths and `adopt(_:from:)` cannot tell they are the
    /// same ones, because `PublicationIdentity.matches` falls back to `normalizedPath` when a
    /// local file has neither a server id nor a content digest — which is the ordinary case.
    ///
    /// Simulated the way it actually happens: a snapshot written for a folder, the folder
    /// moved, and the model restored and rescanned against the new location. Every test in
    /// the repository passed while the shelf was doubled, which is why this one exists.
    @Test("A cached shelf whose files have moved does not double the library")
    @MainActor
    func aMovedLibraryIsNotRestoredTwice() async throws {
        let documents = try documents()
        let old = documents.appending(path: "before")
        let new = documents.appending(path: "after")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try file(named: "image-pages.pdf"), to: old.appending(path: "image-pages.pdf"))

        let bookmarks = FolderBookmarks(defaults: try store().defaults)
        let cache = LibraryCache(directory: documents)

        // A session that walked the folder where it used to be, and wrote the snapshot.
        let first = LibraryModel(bookmarks: bookmarks, documents: old, cache: cache)
        await first.rescan()
        #expect(first.publications.count == 1, "the first walk did not find the fixture")

        // The same library, at a path that no longer resolves — a reinstall, in one move.
        try FileManager.default.moveItem(at: old, to: new)

        let second = LibraryModel(bookmarks: bookmarks, documents: new, cache: cache)
        second.restoreCachedLibrary()
        await second.rescan()
        #expect(
            second.publications.count == 1,
            """
            The shelf holds \(second.publications.count) rows for one publication. A cached \
            row whose file has moved was restored beside the one the scan found, and the \
            reader sees the same book twice — the second of them unopenable.
            """
        )
    }

}
