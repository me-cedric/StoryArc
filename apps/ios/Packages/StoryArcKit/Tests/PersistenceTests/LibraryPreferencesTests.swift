import Foundation
import Testing

import StoryArcCore
@testable import Persistence

/// `library-browsing` requires filters and the layout to survive leaving the
/// library. A private `UserDefaults` suite is used rather than a mock: what is
/// being asserted is that the values actually round-trip through storage.
///
/// Android's `LibraryPreferencesTest` asserts the same three things.
@Suite("Library preferences")
struct LibraryPreferencesTests {
    /// A private defaults suite, and the means to throw it away afterwards.
    private struct Suite {
        let preferences: LibraryPreferences
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Suite {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Suite(preferences: LibraryPreferences(defaults: defaults), defaults: defaults, name: name)
    }

    @Test("Filters and sorting come back on the next launch")
    func roundTrip() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        preferences.save(
            LibraryQuery(
                readStates: [.inProgress],
                formats: [.cbz, .pdf],
                sort: .lastRead,
                ascending: false
            )
        )

        let restored = preferences.query()
        #expect(restored.readStates == [.inProgress])
        #expect(restored.formats == [.cbz, .pdf])
        #expect(restored.sort == .lastRead)
        #expect(restored.ascending == false)
    }

    @Test("A search term is not remembered")
    func searchIsNotStored() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        // A filter outlives a session. A half-typed search does not, and reopening
        // the app to a library narrowed by yesterday's word reads as a bug.
        preferences.save(LibraryQuery(search: "sandman", sort: .series))

        #expect(preferences.query().search.isEmpty)
        #expect(preferences.query().sort == .series)
    }

    @Test("The layout defaults to the grid and survives a change")
    func layout() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        #expect(preferences.layout() == .grid)
        preferences.save(LibraryLayout.list)
        #expect(preferences.layout() == .list)
    }
}
