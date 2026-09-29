import Foundation
import Testing

import StoryArcCore
@testable import Persistence

/// Where a continuous scroll sits within its current page, kept only on this device.
///
/// A private `UserDefaults` suite, as `LibraryPreferencesTests` uses: this asserts the
/// value actually round-trips through storage, not a mock of it.
@Suite("Scroll offset memory")
struct ScrollOffsetMemoryTests {
    private struct Suite {
        let preferences: ReaderPreferences
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Suite {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Suite(preferences: ReaderPreferences(defaults: defaults), defaults: defaults, name: name)
    }

    private let comic = PublicationIdentity(normalizedPath: "/comics/one.cbz")
    private let novel = PublicationIdentity(normalizedPath: "/books/two.epub")

    @Test("Nothing stored reads as no entry, not zero")
    func nothingStoredIsNil() {
        #expect(ScrollOffsetMemory().entry(for: comic) == nil)
    }

    @Test("A remembered place comes back for that publication and no other")
    func remembersPerPublication() {
        let memory = ScrollOffsetMemory().remembering(0.42, onPage: 3, for: comic)
        #expect(memory.entry(for: comic) == ScrollOffsetMemory.Entry(page: 3, fraction: 0.42))
        #expect(memory.entry(for: novel) == nil)
    }

    @Test("Remembering again for the same publication replaces the page and the fraction")
    func remembersReplace() {
        let memory = ScrollOffsetMemory()
            .remembering(0.2, onPage: 1, for: comic)
            .remembering(0.9, onPage: 4, for: comic)
        #expect(memory.entry(for: comic) == ScrollOffsetMemory.Entry(page: 4, fraction: 0.9))
    }

    @Test("A fraction outside 0...1 is clamped before it is kept")
    func clampsOnTheWayIn() {
        let memory = ScrollOffsetMemory().remembering(4, onPage: 0, for: comic)
        #expect(memory.entry(for: comic)?.fraction == 1)
    }

    @Test("A place survives the round trip through UserDefaults")
    func roundTripsThroughPreferences() throws {
        let suite = try fresh()
        defer { suite.discard() }

        suite.preferences.save(ScrollOffsetMemory().remembering(0.65, onPage: 7, for: comic))

        let entry = suite.preferences.scrollOffsets().entry(for: comic)
        #expect(entry == ScrollOffsetMemory.Entry(page: 7, fraction: 0.65))
    }

    @Test("A fresh suite has never stored anything")
    func freshSuiteIsEmpty() throws {
        let suite = try fresh()
        defer { suite.discard() }

        #expect(suite.preferences.scrollOffsets().entry(for: comic) == nil)
    }
}
