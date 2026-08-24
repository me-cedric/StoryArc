import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// ADR-0006's storage half. The merge rules are tested in `StoryArcCoreTests`;
/// these are about the store finding the right record and keeping the right
/// values.
@Suite("Progress store")
struct ProgressStoreTests {
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

    @Test("A saved position comes back")
    func roundTrip() async throws {
        let store = try store()
        let id = identity(path: "/books/one.cbz")
        try await store.save(
            ReadingProgress(identity: id, position: .page(index: 4, of: 20), updatedAt: .now)
        )

        let found = try await store.progress(for: id)
        #expect(found?.position == .page(index: 4, of: 20))
        #expect(found?.isFinished == false)
    }

    @Test("Nothing recorded returns nothing, rather than a zero position")
    func absent() async throws {
        // A publication never opened and one opened at page 1 are different
        // states, and a library that shows a progress ring on every unread book
        // is useless.
        #expect(try await store().progress(for: identity(path: "/nowhere.cbz")) == nil)
    }

    @Test("Saving again replaces the position rather than adding a record")
    func overwrite() async throws {
        let store = try store()
        let id = identity(path: "/books/one.cbz")
        try await store.save(
            ReadingProgress(identity: id, position: .page(index: 1, of: 20), updatedAt: .now)
        )
        try await store.save(
            ReadingProgress(identity: id, position: .page(index: 9, of: 20), updatedAt: .now)
        )

        #expect(try await store.progress(for: id)?.position == .page(index: 9, of: 20))
        #expect(try await store.recent().count == 1)
    }

    // MARK: - Identity, which is the point of ADR-0006

    @Test("A record written against a path is found again by its digest")
    func identityMerges() async throws {
        // The scenario ADR-0006 exists for: a file read from a folder, then the
        // same file recognised by content after a rename or a move.
        let store = try store()
        let path = identity(path: "/books/one.cbz")
        try await store.save(
            ReadingProgress(identity: path, position: .page(index: 3, of: 10), updatedAt: .now)
        )

        // The same publication, now with a digest as well.
        let both = identity(digest: "abc123", path: "/books/one.cbz")
        try await store.save(
            ReadingProgress(identity: both, position: .page(index: 5, of: 10), updatedAt: .now)
        )

        // Found by digest alone, from a record that began life path-keyed.
        let byDigest = try await store.progress(for: identity(digest: "abc123"))
        #expect(byDigest?.position == .page(index: 5, of: 10))
        #expect(try await store.recent().count == 1, "the two must be one record, not two")
    }

    @Test("A server identifier wins over the other components")
    func serverIdentifierPreferred() async throws {
        let store = try store()
        let source = UUID()
        let served = identity(server: (source, "chapter-9"), digest: "abc123")
        try await store.save(
            ReadingProgress(identity: served, position: .page(index: 7, of: 30), updatedAt: .now)
        )

        // The server is authoritative for its own content, so its key is looked at
        // first and finds the record even with no digest to hand.
        let found = try await store.progress(for: identity(server: (source, "chapter-9")))
        #expect(found?.position == .page(index: 7, of: 30))
    }

    @Test("Two different publications stay two records")
    func distinctPublications() async throws {
        let store = try store()
        try await store.save(
            ReadingProgress(
                identity: identity(path: "/a.cbz"), position: .page(index: 1, of: 5),
                updatedAt: .now
            )
        )
        try await store.save(
            ReadingProgress(
                identity: identity(path: "/b.cbz"), position: .page(index: 2, of: 5),
                updatedAt: .now
            )
        )
        #expect(try await store.recent().count == 2)
    }

    // MARK: - Finished

    @Test("Finished is sticky: a later save does not silently unmark it")
    func finishedIsSticky() async throws {
        // ADR-0006: unmarking a finished publication is a deliberate act, and
        // losing it to a routine save is not something a user would ever want.
        let store = try store()
        let id = identity(path: "/books/done.cbz")
        try await store.save(
            ReadingProgress(
                identity: id, position: .page(index: 19, of: 20), isFinished: true,
                updatedAt: .now
            )
        )
        try await store.save(
            ReadingProgress(
                identity: id, position: .page(index: 2, of: 20), isFinished: false,
                updatedAt: .now
            )
        )

        let found = try await store.progress(for: id)
        #expect(found?.isFinished == true)
        // The position still moves — re-reading a finished book is normal.
        #expect(found?.position == .page(index: 2, of: 20))
    }

    @Test("Forgetting a publication removes it")
    func forget() async throws {
        let store = try store()
        let id = identity(path: "/books/one.cbz")
        try await store.save(
            ReadingProgress(identity: id, position: .page(index: 1, of: 5), updatedAt: .now)
        )
        try await store.forget(id)
        #expect(try await store.progress(for: id) == nil)
    }

    // MARK: - Continue reading

    @Test("Recent is ordered by when it was last read")
    func recentOrder() async throws {
        // What `library-browsing`'s "Continue reading" row is built from, so the
        // order is the feature rather than an implementation detail.
        let store = try store()
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        try await store.save(
            ReadingProgress(
                identity: identity(path: "/old.cbz"), position: .page(index: 1, of: 5),
                updatedAt: old
            )
        )
        try await store.save(
            ReadingProgress(
                identity: identity(path: "/new.cbz"), position: .page(index: 1, of: 5),
                updatedAt: new
            )
        )

        let recent = try await store.recent()
        #expect(recent.first?.identity.normalizedPath == "/new.cbz")
    }

    @Test("Recent respects its limit")
    func recentLimit() async throws {
        let store = try store()
        for index in 0..<5 {
            try await store.save(
                ReadingProgress(
                    identity: identity(path: "/\(index).cbz"),
                    position: .page(index: 1, of: 5),
                    updatedAt: Date(timeIntervalSince1970: Double(index))
                )
            )
        }
        #expect(try await store.recent(limit: 3).count == 3)
    }

    @Test("A reflowable position survives the round trip intact")
    func reflowablePosition() async throws {
        // ADR-0006 stores a locator rather than a page number, because a
        // reflowable page number is a function of the reader's typography.
        let store = try store()
        let id = identity(path: "/book.epub")
        let position = ReadingPosition.reflowable(progression: 0.42, locator: "ch3#p7")
        try await store.save(
            ReadingProgress(identity: id, position: position, updatedAt: .now)
        )
        #expect(try await store.progress(for: id)?.position == position)
    }
}
