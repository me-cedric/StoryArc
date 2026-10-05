import Foundation
@testable import LibraryFeature
import Persistence
import Testing

/// A source already mid-continuation resumes from ``SourceReadProgressStore``, not from page
/// two.
///
/// `sources`' *More from a source than the library holds*: before this store existed,
/// `LibraryModel.partialSources` held the only copy of where a continuation stood, so a
/// relaunch forgot it. ``SourceReadProgress/resuming(from:source:firstSliceRead:)`` is the
/// seam `readServers()` calls to seed a fresh continuation or a resumed one alike, and this
/// is where that seam is tested without a live `LibraryModel`.
@Suite("A source resumes its continuation from disk")
struct SourceReadProgressResumingTests {
    private func store() throws -> SourceReadProgressStore {
        SourceReadProgressStore(defaults: try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID())")))
    }

    @Test("A source already mid-continuation resumes from disk instead of restarting at page two")
    func resumesFromDisk() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()
        store.record(StoredSourceProgress(read: 120, total: 215, nextPage: 3), for: source)

        let progress = SourceReadProgress.resuming(from: store, source: source, firstSliceRead: 60)

        #expect(progress == SourceReadProgress(read: 120, total: 215, nextPage: 3))
    }

    @Test("A source with nothing recorded starts from its first slice, as before")
    func startsFreshWithNothingRecorded() throws {
        let store = try store()
        defer { store.reset() }

        let progress = SourceReadProgress.resuming(from: store, source: UUID(), firstSliceRead: 60)

        #expect(progress == .started(firstSliceRead: 60))
    }
}
