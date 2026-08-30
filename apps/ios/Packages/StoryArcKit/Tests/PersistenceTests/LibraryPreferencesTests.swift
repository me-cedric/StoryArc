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

    @Test("Every filter group comes back, not only the three that were there first")
    func everyGroupRoundTrips() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        preferences.save(
            LibraryQuery(
                readStates: [.finished],
                formats: [.epub],
                languages: ["ja"],
                publishers: ["Fixture Press"],
                genres: ["Superhero"],
                tags: ["reprint"],
                years: YearRange(from: 1986, to: 1999)
            )
        )

        let restored = preferences.query()
        #expect(restored.languages == ["ja"])
        #expect(restored.publishers == ["Fixture Press"])
        #expect(restored.genres == ["Superhero"])
        #expect(restored.tags == ["reprint"])
        #expect(restored.years == YearRange(from: 1986, to: 1999))
        #expect(restored.activeFilterCount == 7)
    }

    @Test("A query stored before the new facets existed still restores its filters")
    func olderStoredQueryStillDecodes() throws {
        let suite = try fresh()
        defer { suite.discard() }

        // Exactly what the build before this one wrote. The synthesized decoder
        // requires every key, so without a decoder that tolerates an absent one this
        // comes back as a fresh query and the reader's filters vanish on the launch
        // after an update — which is what "active filters are still applied" forbids.
        let stored = """
        {"search":"","readStates":["finished"],"formats":["epub"],\
        "languages":["ja"],"sort":"series","ascending":false}
        """
        suite.defaults.set(Data(stored.utf8), forKey: "app.storyarc.libraryQuery")

        let restored = suite.preferences.query()
        #expect(restored.readStates == [.finished])
        #expect(restored.formats == [.epub])
        #expect(restored.languages == ["ja"])
        #expect(restored.sort == .series)
        #expect(restored.ascending == false)
        // And the facets it could not know about are simply off.
        #expect(restored.publishers.isEmpty)
        #expect(restored.years.isActive == false)
    }

    @Test("Recent searches survive the launch the term they came from does not")
    func recentSearches() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        #expect(preferences.recentSearches().isEmpty)
        preferences.save(RecentSearches().recording("sandman").recording("bone"))
        #expect(preferences.recentSearches().terms == ["bone", "sandman"])
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

    @Test("A layout chosen for one scope does not follow the reader into another")
    func layoutIsPerScope() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        // `library-browsing`: covers for the comics on this device, a list for the
        // server's catalogue — "a dense list for one library does not force it
        // everywhere".
        let server = LibraryScope.source(UUID())
        preferences.save(LibraryLayout.list, for: server)

        #expect(preferences.layout(for: server) == .list)
        #expect(preferences.layout(for: .allSources) == .grid)
    }

    @Test("A scope never given a layout falls back rather than resetting to the grid")
    func layoutFallsBack() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        // Written under the key used before the layout was per scope, which is what a
        // reader upgrading has on disk. Handing them the grid again would be the upgrade
        // undoing a choice they made.
        suite.defaults.set("list", forKey: "app.storyarc.libraryLayout")

        #expect(preferences.layout(for: .allSources) == .list)
        #expect(preferences.layout(for: .source(UUID())) == .list)
    }

    @Test("The scope comes back on the next launch, because it persists until changed")
    func scopeRoundTrip() throws {
        let suite = try fresh()
        let preferences = suite.preferences
        defer { suite.discard() }

        let server = LibraryScope.source(UUID())
        preferences.save(LibraryQuery(scope: server))
        #expect(preferences.query().scope == server)
    }
}
