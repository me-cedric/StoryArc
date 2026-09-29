import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// Two chapter identifiers, two rows — and the one-time re-key that closes it.
///
/// `KavitaOrigin.serverIdentifier` used to record a chapter's remote id as its bare number,
/// `"42"`, while the library row, the kept card and a pull's own remote record all built one
/// that reads `"chapter:42"`. A device already holding a position under the bare form must
/// not lose it the moment the two forms are unified — the next open has to find it under the
/// new key. Android's `ProgressStoreServerKeyMigrationTest` asserts the same cases.
@Suite("The one-time re-key of an old server key")
struct ProgressStoreServerKeyMigrationTests {

    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "progress-rekey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A position held under a chapter's bare number is found by its new key on the next open")
    func aBareNumberIsFoundAfterReopening() async throws {
        let store = try folder().appending(path: "progress.store")
        let source = UUID()

        do {
            let first = try ProgressStore(url: store)
            try await first.save(
                ReadingProgress(
                    identity: PublicationIdentity(
                        serverIdentifier: .init(sourceID: source, remoteID: "42")
                    ),
                    position: .page(index: 4, of: 10),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        }

        // A fresh instance over the same file is the next app launch, and the migration
        // runs again at `init` — the whole point of it running there rather than once.
        let reopened = try ProgressStore(url: store)
        let found = try await reopened.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"))
        )
        #expect(found?.position == .page(index: 4, of: 10))
        #expect(try await reopened.recent().count == 1, "the row moved key, it did not double")
    }

    @Test("A position already under the chapter form is left exactly where it was")
    func aChapterFormKeyIsUntouched() async throws {
        let store = try folder().appending(path: "progress.store")
        let source = UUID()

        do {
            let first = try ProgressStore(url: store)
            try await first.save(
                ReadingProgress(
                    identity: PublicationIdentity(
                        serverIdentifier: .init(sourceID: source, remoteID: "chapter:42")
                    ),
                    position: .page(index: 6, of: 10),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        }

        let reopened = try ProgressStore(url: store)
        let found = try await reopened.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "chapter:42"))
        )
        #expect(found?.position == .page(index: 6, of: 10))
        #expect(try await reopened.recent().count == 1)
    }

    @Test("An OPDS server key, which is never all digits, is left alone")
    func anOpdsKeyIsUntouched() async throws {
        let store = try folder().appending(path: "progress.store")
        let source = UUID()

        do {
            let first = try ProgressStore(url: store)
            try await first.save(
                ReadingProgress(
                    identity: PublicationIdentity(
                        serverIdentifier: .init(sourceID: source, remoteID: "opds:99")
                    ),
                    position: .page(index: 2, of: 10),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        }

        let reopened = try ProgressStore(url: store)
        let found = try await reopened.progress(
            for: PublicationIdentity(serverIdentifier: .init(sourceID: source, remoteID: "opds:99"))
        )
        #expect(found?.position == .page(index: 2, of: 10))
    }

    @Test("A record with no server identifier at all is left alone")
    func aPathOnlyRecordIsUntouched() async throws {
        let store = try folder().appending(path: "progress.store")

        do {
            let first = try ProgressStore(url: store)
            try await first.save(
                ReadingProgress(
                    identity: PublicationIdentity(normalizedPath: "/books/one.cbz"),
                    position: .page(index: 1, of: 10),
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        }

        let reopened = try ProgressStore(url: store)
        let found = try await reopened.progress(
            for: PublicationIdentity(normalizedPath: "/books/one.cbz")
        )
        #expect(found?.position == .page(index: 1, of: 10))
    }
}
