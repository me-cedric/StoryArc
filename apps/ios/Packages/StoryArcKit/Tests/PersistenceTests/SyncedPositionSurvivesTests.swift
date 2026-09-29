import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// A save with no synced position keeps the one already stored.
///
/// The field report: a device synced with the server, read one more page, and the next
/// pull raised a "both changed" conflict where there was none. Every reader save sends
/// `syncedPosition: nil` -- only a successful exchange with the server knows one -- so a
/// save that overwrote it unconditionally erased the fact of the sync on the very next
/// page turn. Android mirrors this in `SyncedPositionSurvivesTest`.
///
/// Split from `ProgressStoreTests`, which was at the 400-line cap.
@Suite("A synced position survives a plain save")
struct SyncedPositionSurvivesTests {
    private func store() throws -> ProgressStore { try ProgressStore.inMemory() }

    @Test("A save with no synced position keeps the one already stored")
    func syncedPositionSurvivesAPlainSave() async throws {
        let store = try store()
        let id = PublicationIdentity(normalizedPath: "/books/one.cbz")
        try await store.save(
            ReadingProgress(
                identity: id,
                position: .page(index: 4, of: 20),
                updatedAt: .now,
                syncedPosition: .page(index: 4, of: 20)
            )
        )

        // The ordinary reader save: a new position, and nothing said about sync.
        try await store.save(
            ReadingProgress(identity: id, position: .page(index: 5, of: 20), updatedAt: .now)
        )

        let found = try await store.progress(for: id)
        #expect(found?.position == .page(index: 5, of: 20))
        #expect(found?.syncedPosition == .page(index: 4, of: 20))
    }
}
