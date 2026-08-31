import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What deleting a shelf does, and — the part the reader is promised — what it does not.
///
/// `collections-and-reading-lists`: deleting a collection is confirmed, and the confirmation
/// "states plainly that the publications themselves are not deleted". A dialogue's wording
/// is not testable here; that the wording is *true* is, and it is the half that would rot
/// silently. The other half is the gap itself: a ``ShelfDeletion`` that exists has changed
/// nothing yet, which is the whole difference from the swipe that used to delete outright.
///
/// Android's `ShelfDeletionTest` asserts these cases one for one.
@Suite("Shelf deletion")
struct ShelfDeletionTests {

    // MARK: - Fixtures

    private func shelves() -> Shelves {
        Shelves(
            collections: [
                PublicationCollection(name: "Image Comics", members: ["a", "b"]),
                PublicationCollection(name: "To read with my kid", members: ["b", "c"])
            ],
            lists: [
                ReadingList(name: "Crossover", entries: ["a", "c"]),
                ReadingList(name: "Recommended path", entries: ["b"])
            ]
        )
    }

    // MARK: - Tests

    @Test("Asking to delete deletes nothing until it is confirmed")
    func askingChangesNothing() throws {
        let before = shelves()
        let collection = try #require(before.collections.first)
        _ = ShelfDeletion(collection)
        #expect(before.collections.count == 2)
        #expect(before.collections.contains { $0.id == collection.id })
    }

    @Test("Confirming removes that collection and no other shelf")
    func confirmingCollection() throws {
        let before = shelves()
        let collection = try #require(before.collections.first)
        let after = ShelfDeletion(collection).apply(to: before)

        #expect(after.collections.map(\.name) == ["To read with my kid"])
        #expect(after.lists.count == before.lists.count)
    }

    @Test("Confirming removes that reading list and leaves the collections alone")
    func confirmingList() throws {
        let before = shelves()
        let list = try #require(before.lists.first)
        let after = ShelfDeletion(list).apply(to: before)

        #expect(after.lists.map(\.name) == ["Recommended path"])
        #expect(after.collections.count == before.collections.count)
    }

    /// The sentence the dialogue says, held up by what a deletion can reach. A shelf holds
    /// identities; every other shelf still holds the ones it held, and nothing here can
    /// touch the library the identities point into.
    @Test("The publications stay: another shelf holding the same ones still holds them")
    func publicationsSurvive() throws {
        let before = shelves()
        let collection = try #require(before.collections.first)
        let after = ShelfDeletion(collection).apply(to: before)

        #expect(after.collections.first?.members == ["b", "c"])
        #expect(after.lists.first?.entries == ["a", "c"])
    }

    @Test("A deletion carries the shelf's name, so the question can say which one")
    func namesTheShelf() throws {
        let before = shelves()
        let collection = try #require(before.collections.first)
        let list = try #require(before.lists.first)

        #expect(ShelfDeletion(collection).name == "Image Comics")
        #expect(ShelfDeletion(collection).kind == .collection)
        #expect(ShelfDeletion(list).name == "Crossover")
        #expect(ShelfDeletion(list).kind == .list)
    }

    /// The kind is what dispatches, not the identity. Shown with the pathological case the
    /// two sections make possible in principle: one identity, two shelves, and deleting one
    /// of them must not take the other with it.
    @Test("The kind decides which shelf goes, even when an identity is shared")
    func kindDecides() {
        let id = UUID()
        let collection = PublicationCollection(id: id, name: "Crossover", members: ["a"])
        let list = ReadingList(id: id, name: "Crossover", entries: ["a"])
        let before = Shelves(collections: [collection], lists: [list])

        #expect(ShelfDeletion(collection).apply(to: before).lists.count == 1)
        #expect(ShelfDeletion(collection).apply(to: before).collections.isEmpty)
        #expect(ShelfDeletion(list).apply(to: before).collections.count == 1)
        #expect(ShelfDeletion(list).apply(to: before).lists.isEmpty)
    }
}
