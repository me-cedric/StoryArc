import Foundation
import Testing

@testable import Persistence

/// Which series a Kavita continuation could not read, kept so they are retried rather than
/// lost until the whole continuation runs again. Android's `KavitaFailedSeriesStoreTest`
/// asserts the same cases.
@Suite("Kavita failed series store")
struct KavitaFailedSeriesStoreTests {
    private func store() throws -> KavitaFailedSeriesStore {
        let defaults = try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID())"))
        return KavitaFailedSeriesStore(defaults: defaults)
    }

    @Test("A source nothing has failed has nothing pending")
    func emptyStore() throws {
        let store = try store()
        defer { store.reset() }
        #expect(store.pending(for: UUID()).isEmpty)
    }

    @Test("What was recorded as failing comes back whole")
    func recordsAndReads() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()

        store.record([12, 47], for: source)

        #expect(store.pending(for: source) == [12, 47])
    }

    @Test("Recording an empty set forgets the source, which is a retry pass that succeeded")
    func recordingEmptySetForgets() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()
        store.record([12, 47], for: source)

        store.record([], for: source)

        #expect(store.pending(for: source).isEmpty)
    }

    @Test("Recording replaces the whole set, for that source alone")
    func recordingReplacesWholeSet() throws {
        let store = try store()
        defer { store.reset() }
        let source = UUID()
        let other = UUID()
        store.record([99], for: other)

        store.record([12, 47], for: source)
        store.record([47], for: source)

        #expect(store.pending(for: source) == [47])
        #expect(store.pending(for: other) == [99])
    }
}
