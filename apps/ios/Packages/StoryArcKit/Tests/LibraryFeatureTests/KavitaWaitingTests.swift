import Testing

@testable import LibraryFeature

/// Task 19.8: a Kavita server that has been asked and has not answered used to draw an empty
/// list on iOS, indistinguishable from a server with nothing in it, while Android replaced
/// the whole screen with a full-body spinner. Both now draw placeholder rows or cells
/// instead.
///
/// The condition that picks placeholders over the real content is pulled out beside each
/// view — same reason as ``detailSummary(of:)`` in `DetailAbsencesTests.swift`: free and
/// pure so it can be asserted without composing a view. Android asserts the same two
/// moments by composing the screen in `KavitaWaitingTest.kt`, because Robolectric lets it
/// draw what iOS can only compute on a host.
@Suite("Kavita placeholders while the server answers")
struct KavitaWaitingTests {

    @Test("Loading with nothing arrived yet and no failure draws placeholders")
    func loadingWithNothingYetDrawsPlaceholders() {
        #expect(kavitaShowsLibraryPlaceholders(failure: nil, isLoading: true, hasLibraries: false))
    }

    @Test("A library already arrived stops the placeholders even mid-request")
    func arrivedLibraryStopsPlaceholders() {
        #expect(!kavitaShowsLibraryPlaceholders(failure: nil, isLoading: true, hasLibraries: true))
    }

    @Test("Done loading stops the placeholders")
    func doneLoadingStopsPlaceholders() {
        #expect(!kavitaShowsLibraryPlaceholders(failure: nil, isLoading: false, hasLibraries: false))
    }

    @Test("A failure shows its own sentence instead of placeholders")
    func failureStopsPlaceholders() {
        #expect(!kavitaShowsLibraryPlaceholders(failure: "offline", isLoading: true, hasLibraries: false))
    }

    @Test("Series not yet loaded and no failure draws placeholder cells")
    func seriesNotLoadedDrawsPlaceholders() {
        #expect(kavitaShowsSeriesPlaceholders(failure: nil, hasLoaded: false))
    }

    @Test("Series already loaded stops the placeholder cells")
    func seriesLoadedStopsPlaceholders() {
        #expect(!kavitaShowsSeriesPlaceholders(failure: nil, hasLoaded: true))
    }

    @Test("A series failure shows its own sentence instead of placeholder cells")
    func seriesFailureStopsPlaceholders() {
        #expect(!kavitaShowsSeriesPlaceholders(failure: "offline", hasLoaded: false))
    }
}
