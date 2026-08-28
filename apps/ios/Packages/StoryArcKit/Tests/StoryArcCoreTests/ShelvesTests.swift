import Foundation
import Testing

@testable import StoryArcCore

@Suite("Collections and reading lists")
struct ShelvesTests {
    private let collectionID = UUID()
    private let listID = UUID()

    private func shelves() -> Shelves {
        Shelves()
            .adding(PublicationCollection(id: collectionID, name: "Image Comics"))
            .adding(ReadingList(id: listID, name: "Crossover"))
    }

    @Test("A collection holds each publication once, in no order")
    func collectionIsASet() throws {
        let shelves = self.shelves()
            .adding(["a", "b"], to: collectionID)
            .adding(["b", "c"], to: collectionID)
        #expect(try #require(shelves.collections.first).members == ["a", "b", "c"])
    }

    @Test("A reading list keeps the order entries were added in")
    func listKeepsOrder() throws {
        let shelves = self.shelves()
            .appending(["c", "a"], to: listID)
            .appending(["b", "a"], to: listID)
        // "a" is not added twice, and "b" lands after it rather than being sorted in.
        #expect(try #require(shelves.lists.first).entries == ["c", "a", "b"])
    }

    @Test("A publication can be in any number of collections")
    func manyCollections() {
        let second = UUID()
        let shelves = self.shelves()
            .adding(PublicationCollection(id: second, name: "To read with my kid"))
            .adding(["a"], to: collectionID)
            .adding(["a"], to: second)
        #expect(shelves.collections(containing: "a").count == 2)
        #expect(shelves.collections(containing: "b").isEmpty)
    }

    @Test("What comes next is the next entry in the list, not in a series")
    func nextInList() throws {
        // `collections-and-reading-lists`: "the next entry in list order is offered,
        // regardless of series or source".
        let shelves = self.shelves().appending(["x", "y", "z"], to: listID)
        let list = try #require(shelves.lists.first)
        #expect(list.next(after: "x") == "y")
        #expect(list.next(after: "z") == nil)
        #expect(list.next(after: "absent") == nil)
    }

    @Test("Position is how far the reader has got, not how many they have read")
    func positionStopsAtTheFirstGap() throws {
        // A reader who skipped ahead and read entry three has not read one and two, and a
        // list claiming three of four would be telling them they had.
        let shelves = self.shelves().appending(["a", "b", "c", "d"], to: listID)
        let list = try #require(shelves.lists.first)
        #expect(list.position { ["a", "c"].contains($0) } == 1)
        #expect(list.position { _ in true } == 4)
        #expect(list.position { _ in false } == 0)
    }

    @Test("A drag downwards lands where it was dropped")
    func movingDown() throws {
        let shelves = self.shelves()
            .appending(["a", "b", "c"], to: listID)
            .moving("a", to: 2, inList: listID)
        #expect(try #require(shelves.lists.first).entries == ["b", "a", "c"])
    }

    @Test("A drag upwards lands where it was dropped")
    func movingUp() throws {
        let shelves = self.shelves()
            .appending(["a", "b", "c"], to: listID)
            .moving("c", to: 0, inList: listID)
        #expect(try #require(shelves.lists.first).entries == ["c", "a", "b"])
    }

    @Test("A cover the reader chose has to be in the collection")
    func coverMustBeAMember() throws {
        let shelves = self.shelves()
            .adding(["a"], to: collectionID)
            .settingCover("b", on: collectionID)
        #expect(try #require(shelves.collections.first).coverMemberID == nil)

        let chosen = shelves.settingCover("a", on: collectionID)
        #expect(try #require(chosen.collections.first).coverMemberID == "a")
    }

    @Test("Removing the chosen cover's publication clears the cover")
    func coverFollowsMembership() throws {
        // Left alone it would show a book the collection no longer contains.
        let shelves = self.shelves()
            .adding(["a", "b"], to: collectionID)
            .settingCover("a", on: collectionID)
            .removing(["a"], from: collectionID)
        #expect(try #require(shelves.collections.first).coverMemberID == nil)
    }

    @Test("A blank name is refused rather than stored")
    func blankNamesAreRefused() throws {
        let shelves = self.shelves()
            .renaming(collection: collectionID, to: "   ")
            .renaming(list: listID, to: "")
        #expect(try #require(shelves.collections.first).name == "Image Comics")
        #expect(try #require(shelves.lists.first).name == "Crossover")
    }

    @Test("Removing a source takes its groupings and leaves the reader's own")
    func removingASource() {
        let source = UUID()
        let shelves = self.shelves()
            .adding(PublicationCollection(name: "From the server", origin: .server(source)))
            .adding(ReadingList(name: "Server list", origin: .server(source)))
            .removingAll(from: source)
        #expect(shelves.collections.map(\.name) == ["Image Comics"])
        #expect(shelves.lists.map(\.name) == ["Crossover"])
    }

    @Test("Deleting a grouping leaves the other kind alone")
    func deletingIsPerKind() {
        let shelves = self.shelves().deleting(collection: collectionID)
        #expect(shelves.collections.isEmpty)
        #expect(shelves.lists.count == 1)
    }
}

/// What a list says comes next, when it disagrees with the series.
@Suite("Next in a reading list")
struct ReadingListNextTests {
    @Test("An unavailable entry does not stop the flow")
    func skipsPastAnUnavailableEntry() {
        // `collections-and-reading-lists`: an unavailable entry "does not break the
        // ordering or the next flow". The list still knows what follows it; whether the
        // caller can show that is the caller's problem.
        let list = ReadingList(name: "Crossover", entries: ["a", "gone", "c"])
        #expect(list.next(after: "a") == "gone")
        #expect(list.next(after: "gone") == "c")
    }

    @Test("The last entry has no next")
    func theEndIsTheEnd() {
        let list = ReadingList(name: "Crossover", entries: ["a", "b"])
        #expect(list.next(after: "b") == nil)
    }
}
