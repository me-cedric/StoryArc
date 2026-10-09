import Foundation
import Kavita
import Persistence
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which local record a server's chapter is, when the two do not agree on a path.
///
/// A pull has a chapter id and the store keys on a publication identity. The browser's
/// chapter-to-publication table bridges them, and it holds whichever publication id the
/// chapter was *opened* as — which is not the id of the copy the record was written under
/// once the same chapter has been reached two ways. ADR-0006's first rule is what closes
/// that, and this is the first assertion `KavitaSync` has ever had.
/// Android's `KavitaPullIdentityTest` asserts the same cases.
@Suite("A pull finds the record its chapter belongs to")
struct KavitaPullIdentityTests {
    private let source = UUID()

    private func kavita() throws -> KavitaProgressStore {
        KavitaProgressStore(
            defaults: try #require(UserDefaults(suiteName: "kavita-pull-\(UUID().uuidString)"))
        )
    }

    private func origin(chapterId: Int = 42) -> KavitaOrigin {
        KavitaOrigin(
            sourceId: source.uuidString,
            libraryId: 1,
            seriesId: 7,
            volumeId: 3,
            chapterId: chapterId
        )
    }

    @Test("A chapter whose record was written under another path is still found")
    func aRecordUnderAnotherPathIsFound() async throws {
        // The reader kept the chapter offline, so the record carries the download's path.
        // The browser then opened it from the server, and remembers that copy's id. Only
        // the chapter id is common to both.
        let progress = try ProgressStore.inMemory()
        let kavita = try kavita()
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(
                    // The form `KavitaOrigin.serverIdentifier` builds, and the one the
                    // library row and the kept card already used.
                    serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"),
                    normalizedPath: "/downloads/Bone 01.cbz"
                ),
                position: .page(index: 4, of: 10),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        kavita.remember(origin(), for: "path:/caches/Kavita/42/Bone 1.cbz")

        await KavitaSync.pull(
            [KavitaChapter(id: 42, number: "1", pages: 10, pagesRead: 8)],
            in: kavita,
            into: progress
        )

        let read = try await progress.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"))
        )
        #expect(read?.position == .page(index: 7, of: 10), "the server was further ahead")
        #expect(try await progress.recent().count == 1, "one chapter, one record")
    }

    @Test("A chapter this device has never opened, and has no local record, is left alone")
    func anUnknownChapterIsSkipped() async throws {
        // The position is real and the publication is not. Inventing an identity for it
        // would be inventing a reading.
        let progress = try ProgressStore.inMemory()

        await KavitaSync.pull(
            [KavitaChapter(id: 99, number: "1", pages: 10, pagesRead: 8)],
            in: try kavita(),
            into: progress
        )

        #expect(try await progress.recent().isEmpty)
    }

    @Test("A chapter the browser never opened still merges, by the identity its own library row carries")
    func aChapterNeverOpenedThroughTheBrowserStillMerges() async throws {
        // The library grid opened this row directly and read some of it -- a path that
        // never calls `KavitaProgressStore.remember`, unlike the browser's own. The
        // defect: with no remembered origin, the pull used to skip the chapter outright,
        // even though the row's own identity -- `chapter:<id>`, the same form the browser
        // builds -- already names a local record.
        let progress = try ProgressStore.inMemory()
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42")),
                position: .page(index: 3, of: 10),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        await KavitaSync.pull(
            [KavitaChapter(id: 42, number: "1", pages: 10, pagesRead: 8)],
            in: try kavita(),
            into: progress,
            of: source.uuidString
        )

        let read = try await progress.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"))
        )
        #expect(read?.position == .page(index: 7, of: 10), "the server was further ahead")
    }

    @Test("A chapter the server has finished is adopted, even though the local record was not")
    func serverFinishedIsAdopted() async throws {
        let progress = try ProgressStore.inMemory()
        let kavita = try kavita()
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(
                    serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"),
                    normalizedPath: "/downloads/Bone 01.cbz"
                ),
                position: .page(index: 4, of: 10),
                isFinished: false,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        kavita.remember(origin(), for: "path:/caches/Kavita/42/Bone 1.cbz")

        // The defect: this used to carry `held.isFinished` (false) forward unchanged, so
        // the merge's finished rule never saw a server that had finished a chapter this
        // device had not.
        await KavitaSync.pull(
            [KavitaChapter(id: 42, number: "1", pages: 10, pagesRead: 10)],
            in: kavita,
            into: progress
        )

        let read = try await progress.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"))
        )
        #expect(read?.isFinished == true)
    }

    @Test("A server ahead of a reflowable record is adopted as a fraction, not a page")
    func serverAheadOfAReflowableRecordIsAFraction() async throws {
        // The defect: the remote candidate was always a page, so an EPUB's own record
        // that the server was ahead of adopted a page position -- which this reader
        // cannot open, and reopened the book at its first page. Android's
        // `KavitaPullIdentityTest` asserts the same case.
        let progress = try ProgressStore.inMemory()
        let kavita = try kavita()
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(
                    serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"),
                    normalizedPath: "/downloads/Bone 01.epub"
                ),
                position: .reflowable(progression: 0.2, locator: "{}"),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        kavita.remember(origin(), for: "path:/caches/Kavita/42/Bone 1.epub")

        await KavitaSync.pull(
            [KavitaChapter(id: 42, number: "1", pages: 10, pagesRead: 8)],
            in: kavita,
            into: progress
        )

        let read = try await progress.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"))
        )
        guard case let .reflowable(fraction, locator, _) = read?.position else {
            Issue.record("expected a reflowable position, got \(String(describing: read?.position))")
            return
        }
        #expect(fraction == ReadingPosition.page(index: 7, of: 10).fraction)
        #expect(locator.isEmpty)
    }

    @Test("A genuine conflict is named for the reader, by the chapter's own title")
    func aGenuineConflictIsNamedForTheReader() async throws {
        // D3: the notice must name what changed, and only the chapter a pull is still
        // holding carries a title -- `ProgressPull.Conflict` alone does not.
        let progress = try ProgressStore.inMemory()
        let kavita = try kavita()
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(
                    serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"),
                    normalizedPath: "/downloads/Bone 01.cbz"
                ),
                position: .page(index: 3, of: 10),
                updatedAt: Date(timeIntervalSince1970: 1_000),
                syncedPosition: .page(index: 1, of: 10)
            )
        )
        kavita.remember(origin(), for: "path:/caches/Kavita/42/Bone 1.cbz")

        let conflicts = await KavitaSync.pull(
            [KavitaChapter(id: 42, number: "1", title: "Bone", pages: 10, pagesRead: 9)],
            in: kavita,
            into: progress
        )

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.title == "Bone")
        #expect(conflicts.first?.discarded == .page(index: 3, of: 10))
    }

    @Test("A record written before server identifiers existed is still found by its id")
    func theStableIdRemainsTheFallback() async throws {
        // Every position in the shipped app was written against a path alone, and the
        // browser remembered that same path. The fallback is the only route to those.
        let progress = try ProgressStore.inMemory()
        let kavita = try kavita()
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(normalizedPath: "/caches/Kavita/42/Bone 1.cbz"),
                position: .page(index: 4, of: 10),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        kavita.remember(origin(), for: "path:/caches/Kavita/42/Bone 1.cbz")

        await KavitaSync.pull(
            [KavitaChapter(id: 42, number: "1", pages: 10, pagesRead: 8)],
            in: kavita,
            into: progress
        )

        let read = try await progress.progress(
            for: PublicationIdentity(normalizedPath: "/caches/Kavita/42/Bone 1.cbz")
        )
        #expect(read?.position == .page(index: 7, of: 10))
    }
}
