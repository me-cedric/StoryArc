import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A real scan of a real file, and the reading position that has to survive renaming it.
///
/// `ProgressStore.link(_:)` was written to close this window and nothing called it. Every
/// position the shipped app wrote carries a path and nothing else, so the first rename lost
/// it. `save(_:)` fills the digest in as well, but only when the reader opens the
/// publication again — a reader who tidies their folder first never gets that far.
///
/// So these drive the whole seam: a legacy record, a scan that learns the file's digest, a
/// rename, and the position still found. `ProgressStoreTests` asserts the store's own rules;
/// this asserts that the library actually hands a scan's identities to it.
///
/// Android asserts the same behaviour in `ProgressStoreTest.aScansIdentitiesSurviveARename`
/// and guards the wiring in `ScanLinksProgressTest`.
@Suite("A scan links what it learns")
@MainActor
struct ScanLinksProgressTests {

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

    /// A throwaway folder holding one corpus comic under a name of our choosing.
    private func folder(_ fixture: String, named name: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "scan-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: fixture),
            to: root.appending(path: name)
        )
        return root
    }

    /// A model scanning one folder, with its cached shelf inside that folder.
    ///
    /// The cache directory is handed over rather than left to default for the reason
    /// `SkippedScanTests` gives: the default is the machine's caches directory, which every
    /// model in the process would share.
    private func model(scanning folder: URL, progress: ProgressStore?) -> LibraryModel {
        LibraryModel(progress: progress, documents: folder, cache: LibraryCache(directory: folder))
    }

    /// The position a reader left behind before any digest existed: a path and nothing else.
    private func recordPathOnlyPosition(
        in store: ProgressStore,
        at file: URL,
        page: Int = 9,
        of total: Int = 30,
        when: Date = Date(timeIntervalSince1970: 1_000)
    ) async throws {
        try await store.save(
            ReadingProgress(
                identity: PublicationIdentity(normalizedPath: file.path),
                position: .page(index: page, of: total),
                updatedAt: when
            )
        )
    }

    @Test("A scanned publication keeps its position across a rename")
    func aScanLinksTheDigestBeforeTheRenameHappens() async throws {
        let root = try folder("comics/single-page.cbz", named: "one.cbz")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProgressStore.inMemory()
        try await recordPathOnlyPosition(in: store, at: root.appending(path: "one.cbz"))

        // The scan meets the file and learns what it is. Nothing has moved yet.
        await model(scanning: root, progress: store).rescan()

        // Then the reader tidies their folder.
        try FileManager.default.moveItem(
            at: root.appending(path: "one.cbz"), to: root.appending(path: "two.cbz")
        )
        let after = model(scanning: root, progress: store)
        await after.rescan()

        let renamed = try #require(after.publications.first)
        #expect(renamed.identity.normalizedPath?.hasSuffix("two.cbz") == true)
        #expect(try await store.progress(for: renamed.identity)?.position == .page(index: 9, of: 30))
    }

    @Test("Without the scan's identities the same rename still loses the position")
    func withoutTheLinkTheRenameIsStillLost() async throws {
        // The assertion that stops the test above passing on its own. The library scans
        // exactly as before; only the store is kept out of it, which is the shipped state.
        let root = try folder("comics/single-page.cbz", named: "one.cbz")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProgressStore.inMemory()
        try await recordPathOnlyPosition(in: store, at: root.appending(path: "one.cbz"))

        await model(scanning: root, progress: nil).rescan()

        try FileManager.default.moveItem(
            at: root.appending(path: "one.cbz"), to: root.appending(path: "two.cbz")
        )
        let after = model(scanning: root, progress: nil)
        await after.rescan()

        let renamed = try #require(after.publications.first)
        #expect(try await store.progress(for: renamed.identity) == nil)
    }

    @Test("A second scan of a linked library writes nothing")
    func aSecondScanWritesNothing() async throws {
        let root = try folder("comics/single-page.cbz", named: "one.cbz")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProgressStore.inMemory()
        try await recordPathOnlyPosition(in: store, at: root.appending(path: "one.cbz"))

        let library = model(scanning: root, progress: store)
        await library.rescan()
        await library.rescan()

        // `link` reports whether anything was new. After a scan has run, nothing is —
        // which is what lets a whole library be passed through it on every launch.
        let publication = try #require(library.publications.first)
        #expect(try await store.link(publication.identity) == false)
    }

    @Test("A scan leaves the Continue reading order alone")
    func continueReadingKeepsItsOrder() async throws {
        // Learning a file's digest is not reading it. A backfill that restamped
        // `updatedAt` would reorder the whole row on one launch.
        let root = try folder("comics/single-page.cbz", named: "first.cbz")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/natural-sort.cbz"),
            to: root.appending(path: "second.cbz")
        )
        let store = try ProgressStore.inMemory()
        try await recordPathOnlyPosition(
            in: store, at: root.appending(path: "first.cbz"), when: Date(timeIntervalSince1970: 10)
        )
        try await recordPathOnlyPosition(
            in: store, at: root.appending(path: "second.cbz"), when: Date(timeIntervalSince1970: 20)
        )
        let before = try await store.recent()

        await model(scanning: root, progress: store).rescan()

        let after = try await store.recent()
        #expect(after.map(\.updatedAt) == before.map(\.updatedAt))
        #expect(after.map(\.position) == before.map(\.position))
        #expect(after.count == 2)
    }
}
