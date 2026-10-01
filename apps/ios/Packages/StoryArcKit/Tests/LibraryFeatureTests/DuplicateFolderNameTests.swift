import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// 10.3: two folders picked under the same name are two sources, not one.
///
/// `LibrarySources.register` matched a folder to a source by `url.lastPathComponent`, and
/// `FolderBookmarks` keyed its own entries the same way. So a second folder named "Comics"
/// found the first one's row rather than getting its own, `source(of:)` and `folder(of:)`
/// could not tell the two apart, and removing either source's bookmark removed both.
@Suite("Two folders, the same name")
@MainActor
struct DuplicateFolderNameTests {
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

    /// A folder literally named "Comics", holding one comic, under a parent of its own —
    /// so two calls give two different places that happen to share a last path component.
    private func comicsFolder(holding fixture: String) throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "dup-\(UUID().uuidString)")
            .appending(path: "Comics")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/\(fixture)"),
            to: folder.appending(path: fixture)
        )
        return folder
    }

    private func documents() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "dup-docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Each becomes its own source, and each keeps its own books")
    func eachIsItsOwnSource() async throws {
        let name = "dup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let bookmarks = FolderBookmarks(defaults: defaults)

        let first = try comicsFolder(holding: "single-page.cbz")
        let second = try comicsFolder(holding: "natural-sort.cbz")
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }

        let model = LibraryModel(bookmarks: bookmarks, documents: stand, cache: LibraryCache(directory: stand))
        model.addFolder(first)
        await model.scanTask?.value
        model.addFolder(second)
        await model.scanTask?.value

        let folderSources = model.registry.sources.filter { $0.kind == .localFolder }
        #expect(folderSources.count == 2, "two folders named Comics became \(folderSources.count) source(s)")

        let firstID = model.registry.sources.first { $0.locator == bookmarks.key(for: first) }?.id
        let secondID = model.registry.sources.first { $0.locator == bookmarks.key(for: second) }?.id
        #expect(firstID != nil)
        #expect(secondID != nil)
        #expect(firstID != secondID)

        let firstBook = model.publications.first {
            model.location(of: $0)?.path.hasPrefix(first.path) == true
        }
        let secondBook = model.publications.first {
            model.location(of: $0)?.path.hasPrefix(second.path) == true
        }
        #expect(firstBook?.sourceID == firstID)
        #expect(secondBook?.sourceID == secondID)
    }

    @Test("Removing one folder's source does not take the other's bookmark with it")
    func removingOneLeavesTheOther() async throws {
        let name = "dup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let bookmarks = FolderBookmarks(defaults: defaults)

        let first = try comicsFolder(holding: "single-page.cbz")
        let second = try comicsFolder(holding: "natural-sort.cbz")
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let stand = try documents()
        defer { try? FileManager.default.removeItem(at: stand) }

        let model = LibraryModel(bookmarks: bookmarks, documents: stand, cache: LibraryCache(directory: stand))
        model.addFolder(first)
        await model.scanTask?.value
        model.addFolder(second)
        await model.scanTask?.value

        let firstSource = try #require(
            model.registry.sources.first { $0.locator == bookmarks.key(for: first) }
        )
        model.remove(firstSource, credentials: nil)

        let restored = FolderBookmarks(defaults: defaults).restore()
        #expect(restored.folders.count == 1, "removing one of two same-named folders left \(restored.folders.count)")
        #expect(
            restored.folders.first?.resolvingSymlinksInPath().path
                == second.resolvingSymlinksInPath().path
        )
    }
}
