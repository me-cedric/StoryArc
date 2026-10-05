import Foundation
@testable import LibraryFeature
import Persistence
import StoryArcCore
import Testing

/// A source already mid-continuation resumes from ``SourceReadProgressStore``, not from page
/// two.
///
/// `sources`' *More from a source than the library holds*: before this store existed,
/// `LibraryModel.partialSources` held the only copy of where a continuation stood, so a
/// relaunch forgot it. ``SourceReadProgress/resumable(in:source:kind:)`` is the seam
/// `adoptPartialSources` calls to seed a fresh continuation or a resumed one alike, and this
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

        let resumed = SourceReadProgress.resumable(in: store, source: source, kind: .kavitaServer)

        #expect(
            SourceReadProgress.resuming(from: resumed, firstSliceRead: 60)
                == SourceReadProgress(read: 120, total: 215, nextPage: 3)
        )
    }

    @Test("A source with nothing recorded starts from its first slice, as before")
    func startsFreshWithNothingRecorded() throws {
        let store = try store()
        defer { store.reset() }

        let resumed = SourceReadProgress.resumable(in: store, source: UUID(), kind: .kavitaServer)

        #expect(SourceReadProgress.resuming(from: resumed, firstSliceRead: 60) == .started(firstSliceRead: 60))
    }

    @Test("A record written before the cursor was stored starts a share and a catalogue over")
    func refusesARecordWithNoCursor() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()
        // What an older build left on disk: the count, and nothing to continue by. Resuming
        // it would ask page four for the share's root, adopt the rows the library already
        // holds, and report about twice the share's real size.
        store.record(StoredSourceProgress(read: 540, total: nil, nextPage: 4), for: source)

        #expect(SourceReadProgress.resumable(in: store, source: source, kind: .networkShare) == nil)
        #expect(SourceReadProgress.resumable(in: store, source: source, kind: .opdsCatalog) == nil)
        // A Kavita page number answers for itself, so the same record is still enough there.
        #expect(SourceReadProgress.resumable(in: store, source: source, kind: .kavitaServer) != nil)
    }

    @Test("A record that carries the cursor its kind continues by is resumed")
    func acceptsARecordWithItsCursor() throws {
        let store = try store()
        defer { store.reset() }
        let share = UUID()
        let catalogue = UUID()
        let link = URL(string: "https://library.example/feed?page=7")
        store.record(StoredSourceProgress(read: 540, nextPage: 4, smbQueue: ["d40", "d41"]), for: share)
        store.record(StoredSourceProgress(read: 180, nextPage: 7, opdsNext: link), for: catalogue)

        #expect(SourceReadProgress.resumable(in: store, source: share, kind: .networkShare)?.smbQueue == ["d40", "d41"])
        #expect(SourceReadProgress.resumable(in: store, source: catalogue, kind: .opdsCatalog)?.opdsNext == link)
    }
}
