import Foundation
@testable import LibraryFeature
import Persistence
import StoryArcCore
import Testing

/// A departed source takes its pending retries with it, and a source that merely finished its
/// read keeps them.
///
/// ``KavitaFailedSeriesStore/clear(for:)``'s own doc says it is "called when the source itself
/// is gone", and nothing called it: a reader who removed a Kavita server left its failed
/// series on disk for the life of the install. The prune loop in `adoptPartialSources` already
/// drops a departed source's read progress, so it is the one place that knows the difference
/// between a source that is gone and a source that is done. Android's
/// `FailedSeriesGoWithTheirSourceTest` is the twin.
@MainActor
@Suite("Failed series go when their source does")
struct FailedSeriesGoWithTheirSourceTests {

    private let sourceID = UUID()
    private let store = KavitaFailedSeriesStore()

    @Test("A source the registry no longer holds loses its pending retries")
    func departedSourceLosesThem() {
        defer { store.record([], for: sourceID) }
        store.record([5, 9], for: sourceID)
        let model = LibraryModel()
        model.partialSources[sourceID] = .started(firstSliceRead: 0)

        // The read that follows a removal reports nothing partial for a source it can no
        // longer see, which is the same thing that happens when a read simply ends.
        model.adoptPartialSources(.init())

        #expect(store.pending(for: sourceID).isEmpty)
    }

    @Test("A source that merely finished its read keeps them")
    func finishedSourceKeepsThem() {
        defer { store.record([], for: sourceID) }
        store.record([5, 9], for: sourceID)
        let model = LibraryModel()
        model.registry = SourceRegistry(
            sources: [Source(id: sourceID, displayName: "Attic", kind: .kavitaServer)]
        )
        model.partialSources[sourceID] = .started(firstSliceRead: 0)

        model.adoptPartialSources(.init())

        // `retryFailedKavitaSeries()` asks for these on every read after the continuation has
        // ended, which is the whole reason that function does not live inside the loop that
        // drives a partial source. Clearing here would make a failed series lost for good.
        #expect(store.pending(for: sourceID) == [5, 9])
    }
}
