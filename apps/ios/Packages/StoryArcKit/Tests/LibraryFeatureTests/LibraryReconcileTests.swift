import Foundation
import Testing

import Formats
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// `local-library`: a returning app reconciles "by comparing file modification times and sizes rather than re-reading
/// every archive". The shelf is what a walk is handed (`LibraryModel.shelfByPath`), and the scanner decides per file
/// (`LibraryScanner.scan`'s `known`). Real files from the committed corpus, as `LibraryShelfLifecycleTests` uses.
@Suite("Library reconcile")
@MainActor
struct LibraryReconcileTests {
    private static let comics: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus.appending(path: "comics")
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    @Test("A second walk hands back an unchanged file's row instead of reopening it, and reads a changed one again")
    func unchangedFilesAreNotReopened() async throws {
        let documents = URL.temporaryDirectory.appending(path: "reconcile-\(UUID().uuidString)")
        let cache = URL.temporaryDirectory.appending(path: "reconcile-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        let file = documents.appending(path: "01.cbz")
        try FileManager.default.copyItem(at: Self.comics.appending(path: "single-page.cbz"), to: file)
        let model = LibraryModel(documents: documents, cache: LibraryCache(directory: cache))
        model.scan(documents)
        await model.scanTask?.value
        let row = try #require(model.publications.first)
        #expect(row.identity.contentDigest != nil, "a local archive is indexed with its content digest")
        #expect(model.shelfByPath()[(file.path as NSString).standardizingPath]?.id == row.id)

        // A row marked so a reuse can be told from a re-read: the walk hands it back only while the file is unchanged.
        var marked = row
        marked.sourceID = UUID()
        let reused = await Self.found(in: documents, known: marked)
        #expect(reused?.sourceID == marked.sourceID, "an unchanged file was opened again")

        try FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: Self.comics.appending(path: "natural-sort.cbz"), to: file)
        let reread = await Self.found(in: documents, known: marked)
        #expect(reread != nil && reread?.sourceID == nil, "a changed file was trusted instead of read again")
    }

    /// The first publication a walk of `folder` finds, with `known` offered for every file.
    private static func found(in folder: URL, known: Publication) async -> Publication? {
        for await event in LibraryScanner.scan(folderAt: folder, known: { _ in known }) {
            if let publication = event.publication { return publication }
        }
        return nil
    }
}
