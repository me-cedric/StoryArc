import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// A status the reader set by hand, for a series whose source reports none.
///
/// Android's `SeriesStatusStoreTest` makes the same claims in the same order.
struct SeriesStatusStoreTests {
    private func store() throws -> SeriesStatusStore {
        let defaults = try #require(UserDefaults(suiteName: "series-status-\(UUID().uuidString)"))
        return SeriesStatusStore(defaults: defaults)
    }

    @Test("A status survives a round trip")
    func roundTrip() throws {
        let store = try store()
        store.set(.completed, for: "Tidal Reach")
        #expect(store.all() == ["Tidal Reach": .completed])
    }

    @Test("Setting a status again for the same series replaces it")
    func replacesRatherThanAdds() throws {
        let store = try store()
        store.set(.ongoing, for: "Tidal Reach")
        store.set(.hiatus, for: "Tidal Reach")
        #expect(store.all() == ["Tidal Reach": .hiatus])
    }

    @Test("Two series keep their own statuses apart")
    func twoSeriesStayApart() throws {
        let store = try store()
        store.set(.ongoing, for: "Tidal Reach")
        store.set(.completed, for: "Nightglass")
        #expect(store.all() == ["Tidal Reach": .ongoing, "Nightglass": .completed])
    }

    @Test("Clearing a series removes only that one")
    func clearRemovesOnlyThatSeries() throws {
        let store = try store()
        store.set(.ongoing, for: "Tidal Reach")
        store.set(.completed, for: "Nightglass")
        store.clear("Tidal Reach")
        #expect(store.all() == ["Nightglass": .completed])
    }

    @Test("A store that was never written to holds nothing")
    func emptyStoreHoldsNothing() throws {
        #expect(try store().all().isEmpty)
    }
}
