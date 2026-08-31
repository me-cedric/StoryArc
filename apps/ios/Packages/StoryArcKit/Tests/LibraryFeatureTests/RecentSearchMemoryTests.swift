import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What survives a launch, what a clear takes with it, and what arriving on the page files.
///
/// `library-browsing`: "when a user opens search, recent queries are offered, and can be
/// cleared". Three pieces already had assertions of their own and none of them covers this
/// one: ``RecentSearchesTests`` pins the *value*'s folding rules, `LibraryPreferencesTests`
/// pins that the store round-trips a list, and neither knows the model exists.
///
/// **The gap that matters is the clear.** ``LibraryModel/clearRecentSearches()`` empties the
/// property *and* writes the empty list back, and only the second half survives the launch a
/// reader takes it to be. Emptying the property alone passes every other suite in this
/// package and hands the list straight back on the next launch.
///
/// **And the arrival.** The term is filed as it is typed — there is no submit action, so
/// there is no later moment to hang the record on — which makes every write to `query` a
/// candidate for filing something. Leaving search sets the term to empty (`AppShell` does
/// exactly that), and reaching the page sets nothing at all. Neither is a search, and a list
/// that grew an entry for arriving on the page would be offering a reader their own
/// navigation back as history.
///
/// Android's half of this task is in `feature/library`, which this agent was told not to
/// touch; see the handoff.
@MainActor
@Suite("Recent search memory")
struct RecentSearchMemoryTests {

    /// A preferences store of its own, so one test cannot read what another wrote.
    private func preferences() throws -> LibraryPreferences {
        LibraryPreferences(
            defaults: try #require(UserDefaults(suiteName: "recents-\(UUID().uuidString)"))
        )
    }

    @Test("Searches typed into one model are offered by the next")
    func searchesSurviveALaunch() throws {
        let preferences = try preferences()
        let model = LibraryModel(preferences: preferences)
        model.query.search = "sandman"
        model.query.search = "bone"

        #expect(model.recentSearches.terms == ["bone", "sandman"])
        // A second model over the same store is what the next launch is.
        #expect(LibraryModel(preferences: preferences).recentSearches.terms == ["bone", "sandman"])
    }

    @Test("Clearing empties the list the next launch is offered, not only this one's")
    func clearingReachesTheStore() throws {
        let preferences = try preferences()
        let model = LibraryModel(preferences: preferences)
        model.query.search = "sandman"
        model.query.search = "bone"

        model.clearRecentSearches()

        #expect(model.recentSearches.isEmpty)
        #expect(
            preferences.recentSearches().isEmpty,
            "The clear did not reach the store, so the next launch offers them again"
        )
        #expect(LibraryModel(preferences: preferences).recentSearches.isEmpty)
    }

    @Test("Reaching the search page records nothing")
    func arrivingRecordsNothing() throws {
        let preferences = try preferences()
        let model = LibraryModel(preferences: preferences)

        // Everything reaching the page does to the query, and nothing it does not: a scope,
        // a sort, a layout — never a term. `LibraryView(surface: .search)` sets no search
        // text of its own.
        model.query.scope = .allSources
        model.query.sort = .title

        #expect(model.recentSearches.isEmpty, "Arriving is not a search")
        #expect(preferences.recentSearches().isEmpty)
    }

    @Test("Leaving search does not file the empty term the shell writes on the way out")
    func leavingRecordsNothing() throws {
        let preferences = try preferences()
        let model = LibraryModel(preferences: preferences)
        model.query.search = "bone"

        // `AppShell.onChange(of: tab)` clears the term when the reader leaves the
        // destination, so the shelf they land on is not still narrowed by it.
        model.query.search = ""

        #expect(model.recentSearches.terms == ["bone"], "The term is kept as history")
        #expect(preferences.recentSearches().terms == ["bone"])
    }
}
