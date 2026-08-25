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
    private func fresh() -> (LibraryPreferences, UserDefaults, String) {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (LibraryPreferences(defaults: defaults), defaults, name)
    }

    @Test("Filters and sorting come back on the next launch")
    func roundTrip() {
        let (preferences, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }

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
    func searchIsNotStored() {
        let (preferences, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }

        // A filter outlives a session. A half-typed search does not, and reopening
        // the app to a library narrowed by yesterday's word reads as a bug.
        preferences.save(LibraryQuery(search: "sandman", sort: .series))

        #expect(preferences.query().search.isEmpty)
        #expect(preferences.query().sort == .series)
    }

    @Test("The layout defaults to the grid and survives a change")
    func layout() {
        let (preferences, defaults, suite) = fresh()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(preferences.layout() == .grid)
        preferences.save(LibraryLayout.list)
        #expect(preferences.layout() == .list)
    }
}
