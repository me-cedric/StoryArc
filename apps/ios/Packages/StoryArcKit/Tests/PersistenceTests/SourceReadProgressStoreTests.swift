import Foundation
import Testing

@testable import Persistence

/// What a source's continuation wrote down, and what a relaunch reads back.
///
/// `sources`' *More from a source than the library holds*: the continuation used to live
/// only in memory, so a relaunch forgot which page a partial source was on and started its
/// background read over from page two. Android's `SourceReadProgressStoreTest` asserts the
/// same cases.
@Suite("Source read progress store")
struct SourceReadProgressStoreTests {
    private func store() throws -> SourceReadProgressStore {
        let defaults = try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID())"))
        return SourceReadProgressStore(defaults: defaults)
    }

    @Test("A source nothing has read has nothing to resume")
    func emptyStore() throws {
        let store = try store()
        defer { store.reset() }
        #expect(store.progress(for: UUID()) == nil)
    }

    @Test("What a continuation recorded comes back whole")
    func recordsAndReads() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()

        store.record(StoredSourceProgress(read: 120, total: 215, nextPage: 3), for: source)

        #expect(store.progress(for: source) == StoredSourceProgress(read: 120, total: 215, nextPage: 3))
    }

    @Test("Recording again replaces the earlier progress, for that source alone")
    func recordingReplaces() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()
        let other = UUID()
        store.record(StoredSourceProgress(read: 60, nextPage: 2), for: other)

        store.record(StoredSourceProgress(read: 60, nextPage: 2), for: source)
        store.record(StoredSourceProgress(read: 120, total: 154, nextPage: 3), for: source)

        #expect(store.progress(for: source) == StoredSourceProgress(read: 120, total: 154, nextPage: 3))
        #expect(store.progress(for: other) == StoredSourceProgress(read: 60, nextPage: 2))
    }

    @Test("A finished source is forgotten")
    func clearForgets() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()
        store.record(StoredSourceProgress(read: 154, total: 154, nextPage: 4), for: source)

        store.clear(for: source)

        #expect(store.progress(for: source) == nil)
    }
}
