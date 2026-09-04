import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What the shelf does between one walk and the next: the empty state, the cached notice,
/// a refresh that adds, and a book that is gone.
///
/// Four behaviours `library-browsing` and `sources` both name, and until now **nothing on
/// either platform asserted any of them** — task 6.2. Two of them were broken and neither
/// broke a test: on iOS nothing ever wrote a snapshot after a walk, so the cached notice
/// could not appear at all, and the reconcile treated "found nothing" and "could see
/// nothing" as one answer.
///
/// Real folders and the real corpus, for `LibraryRestoreTests`' reason: a shelf asserted
/// against a mock proves nothing about a directory a reader can revoke.
///
/// Android's `ShelfLifecycleTest` asserts the same seven, case for case.
@Suite("Shelf lifecycle")
@MainActor
struct LibraryShelfLifecycleTests {

    // MARK: - Places

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

    private func temporary(_ prefix: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func copy(_ fixture: String, as name: String, into folder: URL) throws -> URL {
        let file = folder.appending(path: name)
        try FileManager.default.copyItem(at: Self.corpus.appending(path: "comics/\(fixture)"), to: file)
        return file
    }

    /// A model whose cache and Documents folder are its own, so no test reaches the machine's.
    private func model(cacheIn directory: URL, documents: URL) -> LibraryModel {
        LibraryModel(documents: documents, cache: LibraryCache(directory: directory))
    }

    // MARK: - The empty state

    @Test("A walk that finds nothing leaves the library empty and says it finished")
    func emptyState() async throws {
        // The condition `LibraryContent` branches on for the first thing a reader ever sees.
        // A shelf stuck in `.scanning` draws a spinner for ever, and a shelf that reports
        // publications it does not have draws nothing at all.
        let documents = try temporary("empty-documents")
        let cache = try temporary("empty-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }

        let model = model(cacheIn: cache, documents: documents)
        model.scan(documents)
        await model.scanTask?.value

        #expect(model.publications.isEmpty)
        #expect(model.visible.isEmpty)
        #expect(model.registry.sources.isEmpty)
        #expect(model.scanState == .finished(found: 0, skipped: 0))
    }

    // MARK: - The cached notice

    @Test("A shelf restored from the cache says when it was last refreshed")
    func cachedNoticeAppears() async throws {
        let documents = try temporary("cached-documents")
        let cache = try temporary("cached-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }

        // Written by a first launch, which is what makes this test worth having: nothing on
        // iOS wrote one until 2026-09-05, so `cachedAt` was never set and `CachedNotice` —
        // a drawn view with its own string — could not appear.
        try copy("single-page.cbz", as: "01.cbz", into: documents)
        let first = model(cacheIn: cache, documents: documents)
        first.scan(documents)
        await first.scanTask?.value
        #expect(first.publications.count == 1)

        let second = model(cacheIn: cache, documents: documents)
        second.restoreCachedLibrary()

        #expect(second.publications.count == 1)
        #expect(second.cachedAt != nil, """
            The shelf was restored from the cache and the indicator says nothing. `sources` \
            asks for "a single unobtrusive indicator" stating that content is cached and \
            when it was last refreshed.
            """)
    }

    @Test("A walk that read the folder takes the cached notice down")
    func cachedNoticeLeavesOnAGoodWalk() async throws {
        let documents = try temporary("current-documents")
        let cache = try temporary("current-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)

        let first = model(cacheIn: cache, documents: documents)
        first.scan(documents)
        await first.scanTask?.value

        let second = model(cacheIn: cache, documents: documents)
        second.restoreCachedLibrary()
        try #require(second.cachedAt != nil)
        second.scan(documents)
        await second.scanTask?.value

        #expect(second.cachedAt == nil, """
            The shelf is current and the indicator still calls it cached, which is the \
            indicator lying quietly in the corner.
            """)
    }

    @Test("A walk that could not read the folder keeps the cached notice")
    func cachedNoticeStaysOnAnUnreadableWalk() async throws {
        // Task 5.1, and the reader-facing half of it: a folder whose permission lapsed lists
        // nothing, opens nothing and finishes `0, 0` — the same terminal event as a reader
        // who deleted every book. Being told the shelf is current is exactly wrong at the one
        // moment it is most certainly not.
        let documents = try temporary("locked-documents")
        let cache = try temporary("locked-cache")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: documents.path()
            )
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)

        let first = model(cacheIn: cache, documents: documents)
        first.scan(documents)
        await first.scanTask?.value
        try #require(first.publications.count == 1)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: documents.path())
        try #require(!FileManager.default.isReadableFile(atPath: documents.path()))

        let second = model(cacheIn: cache, documents: documents)
        second.restoreCachedLibrary()
        let restored = try #require(second.cachedAt)
        second.scan(documents)
        await second.scanTask?.value

        #expect(second.cachedAt == restored, """
            A walk that could see nothing took the cached indicator down. It must leave only \
            when a walk genuinely found an empty folder — `sources` promises cached content \
            "remains browsable" when a source cannot be reached.
            """)
    }

    @Test("A walk that lost one subfolder still holds the books that were under it")
    func nothingIsForgottenOnAPartialWalk() async throws {
        // **The case the emptiness rule could never catch.** A walk that finds *nothing*
        // was already treated as evidence of nothing, but a folder that loses one branch
        // still returns rows — so the walk looked complete, and every book under the branch
        // it could not list was removed as though the reader had deleted it.
        let documents = try temporary("partial-documents")
        let cache = try temporary("partial-cache")
        let series = documents.appending(path: "Bone")
        try FileManager.default.createDirectory(at: series, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: series.path()
            )
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)
        try copy("natural-sort.cbz", as: "02.cbz", into: series)

        let model = model(cacheIn: cache, documents: documents)
        model.scan(documents)
        await model.scanTask?.value
        try #require(model.publications.count == 2)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: series.path())
        try #require(!FileManager.default.isReadableFile(atPath: series.path()))
        model.scan(documents)
        await model.scanTask?.value

        #expect(model.publications.count == 2, """
            The books under the subfolder the walk could not list were forgotten. The walk \
            found something, so the emptiness rule did not save them — what it did not see \
            is unaccounted for, not gone.
            """)
    }

    @Test("A walk that could not read the folder at all removes nothing either")
    func nothingIsForgottenOnAnUnreadableWalk() async throws {
        let documents = try temporary("keep-documents")
        let cache = try temporary("keep-cache")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: documents.path()
            )
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)

        let first = model(cacheIn: cache, documents: documents)
        first.scan(documents)
        await first.scanTask?.value
        try #require(first.publications.count == 1)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: documents.path())
        try #require(!FileManager.default.isReadableFile(atPath: documents.path()))

        let second = model(cacheIn: cache, documents: documents)
        second.restoreCachedLibrary()
        second.scan(documents)
        await second.scanTask?.value

        #expect(second.publications.count == 1, """
            A walk that could not list the folder emptied the shelf. What it did not see is \
            unaccounted for, not gone.
            """)
    }

    // MARK: - Incremental refresh

    @Test("A refresh adds what is new without emptying the shelf first")
    func refreshIsIncremental() async throws {
        // `sources`: a refresh updates the view "incrementally rather than clearing it and
        // re-populating". Asserted at the moment it could go wrong — the instant the walk is
        // started, before anything has been found again.
        let documents = try temporary("refresh-documents")
        let cache = try temporary("refresh-cache")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)

        let model = model(cacheIn: cache, documents: documents)
        model.scan(documents)
        await model.scanTask?.value
        let known = try #require(model.publications.first).id

        try copy("natural-sort.cbz", as: "02.cbz", into: documents)
        model.scan(documents)
        #expect(!model.publications.isEmpty, """
            The shelf was emptied when the refresh started. `sources` asks the view to be \
            updated incrementally, and a reader watching sees their library disappear and \
            come back.
            """)
        await model.scanTask?.value

        #expect(model.publications.count == 2)
        #expect(model.publications.contains { $0.id == known }, """
            The publication that was already on the shelf was replaced rather than kept, so \
            every cover it had decoded was thrown away with it.
            """)
    }

    // MARK: - Disappearance

    @Test("A publication the walk no longer finds leaves the shelf, and its progress stays")
    func vanishedIsRemovedAndProgressKept() async throws {
        // `sources`: when a refresh shows a publication "is no longer present in the source",
        // it "is removed from the library view and its reading progress is retained".
        let documents = try temporary("gone-documents")
        let cache = try temporary("gone-cache")
        let store = try temporary("gone-progress")
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: cache)
            try? FileManager.default.removeItem(at: store)
        }
        try copy("single-page.cbz", as: "01.cbz", into: documents)
        let second = try copy("natural-sort.cbz", as: "02.cbz", into: documents)

        let progress = try ProgressStore(url: store.appending(path: "progress.store"))
        let model = LibraryModel(
            progress: progress,
            documents: documents,
            cache: LibraryCache(directory: cache)
        )
        model.scan(documents)
        await model.scanTask?.value
        try #require(model.publications.count == 2)
        let leaving = try #require(model.publications.first { model.location(of: $0) == second })
        let position = ReadingPosition.page(index: 3, of: 8)
        try await progress.save(
            ReadingProgress(identity: leaving.identity, position: position, updatedAt: .now)
        )

        try FileManager.default.removeItem(at: second)
        model.scan(documents)
        await model.scanTask?.value

        #expect(model.publications.count == 1)
        #expect(!model.publications.contains { $0.id == leaving.id })
        let kept = try await progress.progress(for: leaving.identity)
        #expect(kept?.position == position, """
            The reading position went with the file. `sources` retains it, and ADR-0006 makes \
            losing one the thing this app must never do.
            """)
    }
}
