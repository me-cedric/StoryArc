import Testing

@testable import LibraryFeature

/// Task 21.4: a reading-list entry that could not be fetched used to clear its own spinner
/// and say nothing else, which reads as "a spinner and never opens" exactly as the field
/// report named it. `kavitaOpenFailureTitle` is the one decision behind the sentence
/// `KavitaListView` now shows in its place, asserted here because the `Task` that calls it
/// runs from inside a `View`'s body, where a plain test cannot reach it.
@Suite("Kavita reading-list open failures")
struct KavitaOpenFailureTests {

    @Test("A fetch that failed names the entry")
    func failedFetchNamesEntry() {
        #expect(kavitaOpenFailureTitle("Quiet Machines", succeeded: false) == "Quiet Machines")
    }

    @Test("A fetch that succeeded names nothing")
    func succeededFetchNamesNothing() {
        #expect(kavitaOpenFailureTitle("Quiet Machines", succeeded: true) == nil)
    }
}
