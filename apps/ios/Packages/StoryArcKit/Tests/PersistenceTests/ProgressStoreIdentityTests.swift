import Foundation
import StoryArcCore
import SwiftData
import Testing

@testable import Persistence

/// `reading-progress`, *Same publication from two sources*: "the local progress applies,
/// resolved through content identity".
///
/// The half of ADR-0006's identity rule that had no production caller until the Kavita
/// browser built one. Apart from ``ProgressStoreTests`` because that file is at its length
/// limit, not because the subject is different. Android's `ProgressStoreTest` asserts the
/// same cases.
@Suite("The same publication from two sources")
struct ProgressStoreIdentityTests {
    private func store() throws -> ProgressStore { try ProgressStore.inMemory() }

    private func identity(
        server: (UUID, String)? = nil,
        digest: String? = nil,
        path: String? = nil
    ) -> PublicationIdentity {
        PublicationIdentity(
            serverIdentifier: server.map {
                PublicationIdentity.ServerIdentifier(sourceID: $0.0, remoteID: $0.1)
            },
            contentDigest: digest,
            normalizedPath: path
        )
    }

    @Test("A publication read from a folder and then from a server is one record")
    func aFolderCopyAndAServerCopyAreOneRecord() async throws {
        // The server hands back the bytes it was given, so the digest is what joins the
        // two — the server identifier arrives alongside it and must not fork the record.
        let store = try store()
        let source = UUID()
        try await store.save(
            ReadingProgress(
                identity: identity(digest: "bone-01", path: "/books/Bone 01.cbz"),
                position: .page(index: 11, of: 30),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let served = identity(
            server: (source, "42"), digest: "bone-01", path: "/caches/Kavita/42/Bone 1.cbz"
        )
        #expect(try await store.progress(for: served)?.position == .page(index: 11, of: 30))

        try await store.save(
            ReadingProgress(
                identity: served,
                position: .page(index: 19, of: 30),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        #expect(try await store.recent().count == 1, "one publication, one record")
        #expect(
            try await store.progress(for: identity(digest: "bone-01"))?.position
                == .page(index: 19, of: 30)
        )
    }

    @Test("A chapter the server repackaged keeps the record it already had")
    func aRepackagedChapterKeepsItsRecord() async throws {
        // What the digest alone cannot do. A server that re-compresses on the way out
        // hands back different bytes at a different cache path, and every component but
        // the chapter id has moved. This is ADR-0006's first rule doing the one job the
        // other two cannot: "the server is authoritative for its own content".
        let store = try store()
        let source = UUID()
        try await store.save(
            ReadingProgress(
                identity: identity(
                    server: (source, "42"), digest: "packed-once", path: "/caches/Kavita/42/a.cbz"
                ),
                position: .page(index: 7, of: 30),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let again = identity(
            server: (source, "42"), digest: "packed-twice", path: "/caches/Kavita/42/b.cbz"
        )
        #expect(try await store.progress(for: again)?.position == .page(index: 7, of: 30))

        try await store.save(
            ReadingProgress(
                identity: again,
                position: .page(index: 21, of: 30),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        #expect(try await store.recent().count == 1, "one chapter, one record")
    }

    @Test("Two publications that share a title and an author stay two records")
    func lookalikePublicationsNeverMerge() async throws {
        // The assertion that matters most. A merge rule that is too eager destroys
        // reading positions silently, and neither a title nor an author is part of an
        // identity — two printings of one book are two publications until their bytes
        // agree.
        let store = try store()
        let source = UUID()
        try await store.save(
            ReadingProgress(
                identity: identity(
                    server: (source, "42"), digest: "print-one", path: "/books/Bone 01.cbz"
                ),
                position: .page(index: 3, of: 30),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        // The same server, a different chapter.
        try await store.save(
            ReadingProgress(
                identity: identity(
                    server: (source, "43"), digest: "print-two", path: "/books/Bone 01 (copy).cbz"
                ),
                position: .page(index: 5, of: 30),
                updatedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        // The same chapter number, a different server.
        try await store.save(
            ReadingProgress(
                identity: identity(
                    server: (UUID(), "42"), digest: "print-three", path: "/books/Bone 01 (2).cbz"
                ),
                position: .page(index: 8, of: 30),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            )
        )

        #expect(try await store.recent().count == 3)
        #expect(
            try await store.progress(for: identity(server: (source, "42")))?.position
                == .page(index: 3, of: 30)
        )
    }

    @Test("A record written before server identifiers existed still resolves")
    func aPreExistingRecordAdoptsAServerIdentifier() async throws {
        // Every position in the shipped app was written against a path, because nothing
        // ever built a server identifier. Opening the chapter from its server has to find
        // that record and attach to it, not start a second one at page one.
        let store = try store()
        let source = UUID()
        let when = Date(timeIntervalSince1970: 1_000)
        try await store.save(
            ReadingProgress(
                identity: identity(path: "/caches/Kavita/42/Bone 1.cbz"),
                position: .page(index: 9, of: 30),
                updatedAt: when
            )
        )

        let learned = identity(server: (source, "42"), path: "/caches/Kavita/42/Bone 1.cbz")
        #expect(try await store.link(learned) == true)

        let found = try await store.progress(for: identity(server: (source, "42")))
        #expect(found?.position == .page(index: 9, of: 30))
        #expect(found?.updatedAt == when, "learning where it came from is not reading it")
        #expect(try await store.recent().count == 1)
    }

    @Test("A record that gained a server identifier is still filed where it was")
    func adoptingAServerIdentifierDoesNotMoveTheKey() async throws {
        // `progress(forStableID:)` is how a Kavita pull reaches a record: the browser
        // wrote down the publication id the chapter was opened as, and that string has to
        // keep finding the row after the row learns which chapter it is.
        let store = try store()
        let path = "/caches/Kavita/42/Bone 1.cbz"
        try await store.save(
            ReadingProgress(
                identity: identity(path: path), position: .page(index: 9, of: 30), updatedAt: .now
            )
        )
        try await store.link(identity(server: (UUID(), "42"), path: path))

        let found = try await store.progress(forStableID: "path:\(path)")
        #expect(found?.position == .page(index: 9, of: 30))
    }

    private static let containers = "/var/mobile/Containers/Data/Application"

    private func inContainer(_ id: String) -> String {
        "\(Self.containers)/\(id)/Documents/Audiobooks/Tales"
    }

    /// Task 26.4: a folder audiobook was keyed only by its path, and a reinstall changes it.
    @Test("A folder audiobook's position written before a reinstall is found after it")
    func aPositionFromAnOlderContainerIsFound() async throws {
        let store = try store()
        let old = inContainer("0B6E1F5C-2C2E-4C59-8E44-0D6C0A1E2B11")
        try await store.save(
            ReadingProgress(
                identity: identity(path: old),
                position: .listening(part: 2, partCount: 5, offset: 30, of: 90),
                updatedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let now = identity(digest: "folder", path: inContainer("7F3A9D20-5B1C-4E7A-9F02-3C4D5E6F7A88"))
        #expect(try await store.progress(for: now)?.position == .listening(part: 2, partCount: 5, offset: 30, of: 90))
    }

    /// An earlier build imported each copy of a sync document as its own record, so a device
    /// can hold several. They are written here the way that build wrote them.
    @Test("Linking folds the copies of older containers into one record at the current path")
    func linkingFoldsOlderCopiesIntoOne() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = ModelContext(try ProgressStore.opening(ModelConfiguration(url: url)))
        let older = ["0B6E1F5C-2C2E-4C59-8E44-0D6C0A1E2B11", "1C7F2A6D-3D3F-4D6A-9F55-1E7D1B2F3C22"]
        for (index, id) in older.enumerated() {
            legacy.insert(
                StoredProgress(
                    serverKey: nil,
                    contentDigest: nil,
                    normalizedPath: inContainer(id),
                    positionData: try JSONEncoder().encode(
                        ReadingPosition.listening(part: index, partCount: 5, offset: 0, of: 90)
                    ),
                    isFinished: false,
                    finishedAt: nil,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                    syncedPositionData: nil
                )
            )
        }
        try legacy.save()
        let store = try ProgressStore(url: url)
        let current = inContainer("7F3A9D20-5B1C-4E7A-9F02-3C4D5E6F7A88")

        #expect(try await store.link(identity(digest: "folder", path: current)) == true)

        let records = try await store.recent()
        #expect(records.count == 1)
        #expect(records.first?.identity == identity(digest: "folder", path: current))
        #expect(records.first?.position == .listening(part: 1, partCount: 5, offset: 0, of: 90), "the newest stays")
    }
}
