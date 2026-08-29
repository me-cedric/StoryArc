import Foundation
import Testing

@testable import StoryArcCore

@Suite("A bulk action over a selection")
struct BulkSelectionTests {
    private let order = ["a", "b", "c", "d"]

    private func collection(_ members: Set<String>) -> PublicationCollection {
        PublicationCollection(name: "Image Comics", members: members)
    }

    @Test("Adding a selection to a collection touches every member of it")
    func addingCoversTheWholeSelection() {
        let joining = BulkSelection.joining(["a", "b", "c"], of: collection([]))
        #expect(joining == ["a", "b", "c"])
    }

    @Test("A selection of one is a bulk action like any other")
    func aSelectionOfOne() {
        #expect(BulkSelection.joining(["a"], of: collection([])) == ["a"])
        #expect(
            BulkSelection.appending(["a"], to: ReadingList(name: "Crossover"), inOrderOf: order)
                == ["a"]
        )
        #expect(BulkSelection.marking(["a"], read: true, finished: []) == ["a"])
        #expect(BulkSelection.downloading(["a"], onDevice: []) == ["a"])
    }

    @Test("The empty selection does nothing at all")
    func theEmptySelectionDoesNothing() {
        #expect(BulkSelection.joining([], of: collection(["a"])).isEmpty)
        #expect(
            BulkSelection.appending([], to: ReadingList(name: "Crossover"), inOrderOf: order)
                .isEmpty
        )
        #expect(BulkSelection.marking([], read: true, finished: ["a"]).isEmpty)
        #expect(BulkSelection.downloading([], onDevice: ["a"]).isEmpty)
    }

    // What the undo has to put back is what the action moved, and nothing else.
    @Test("A member the collection already holds is not part of what the action changed")
    func alreadyAMemberIsNotAChange() {
        #expect(BulkSelection.joining(["a", "b"], of: collection(["a"])) == ["b"])
    }

    @Test("Entries reach a reading list in the order the library was showing them")
    func appendingKeepsLibraryOrder() {
        let list = ReadingList(name: "Crossover", entries: ["c"])
        #expect(BulkSelection.appending(["d", "a", "c"], to: list, inOrderOf: order) == ["a", "d"])
    }

    @Test("Marking read changes only what was unread, and unread only what was finished")
    func markingChangesOnlyWhatMoves() {
        #expect(BulkSelection.marking(["a", "b"], read: true, finished: ["a"]) == ["b"])
        #expect(BulkSelection.marking(["a", "b"], read: false, finished: ["a"]) == ["a"])
    }

    @Test("A publication already on the device is not fetched a second time")
    func downloadingSkipsWhatIsAlreadyHere() {
        #expect(BulkSelection.downloading(["a", "b"], onDevice: ["a"]) == ["b"])
        #expect(BulkSelection.downloading(["a"], onDevice: ["a"]).isEmpty)
    }
}
