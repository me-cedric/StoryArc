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

    @Test("Nothing stored reads as no fraction, not zero")
    func nothingStoredIsNil() {
        #expect(ScrollOffsetMemory().fraction(for: comic) == nil)
    }

    @Test("A remembered fraction comes back for that publication and no other")
    func remembersPerPublication() {
        let memory = ScrollOffsetMemory().remembering(0.42, for: comic)
        #expect(memory.fraction(for: comic) == 0.42)
        #expect(memory.fraction(for: novel) == nil)
    }

    @Test("Remembering again for the same publication replaces it")
    func remembersReplace() {
        let memory = ScrollOffsetMemory()
            .remembering(0.2, for: comic)
            .remembering(0.9, for: comic)
        #expect(memory.fraction(for: comic) == 0.9)
    }

    @Test("A fraction outside 0...1 is clamped before it is kept")
    func clampsOnTheWayIn() {
        let memory = ScrollOffsetMemory().remembering(4, for: comic)
        #expect(memory.fraction(for: comic) == 1)
    }

    @Test("A fraction survives the round trip through UserDefaults")
    func roundTripsThroughPreferences() throws {
        let suite = try fresh()
        defer { suite.discard() }

        suite.preferences.save(ScrollOffsetMemory().remembering(0.65, for: comic))

        #expect(suite.preferences.scrollOffsets().fraction(for: comic) == 0.65)
    }

    @Test("A fresh suite has never stored anything")
    func freshSuiteIsEmpty() throws {
        let suite = try fresh()
        defer { suite.discard() }

        #expect(suite.preferences.scrollOffsets().fraction(for: comic) == nil)
    }
}
