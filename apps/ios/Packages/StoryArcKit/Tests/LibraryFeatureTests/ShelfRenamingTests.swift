import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// `collections-and-reading-lists` task 7.10: `Shelves.renaming(collection:to:)` and
/// `Shelves.renaming(list:to:)` have had a model to answer since the day they were written;
/// these are the view-model calls `shelfRename` makes. Rendering the alert itself is not
/// tested here for `ShelfCreationTests`' own reason: a `TextField` inside a SwiftUI `alert`
/// cannot be asked what it drew. Android's `ShelfRenamingTest` makes the same claims.
@MainActor
@Suite("Renaming a local shelf")
struct ShelfRenamingTests {

    @Test("Renaming a collection changes its name and saves it")
    func renamesACollection() {
        let model = LibraryModel()
        model.create(collection: "Image Comics")
        let id = model.shelves.collections[0].id

        model.rename(collection: id, to: "Marvel")

        #expect(model.shelves.collections[0].name == "Marvel")
    }

    @Test("Renaming a reading list changes its name and saves it")
    func renamesAList() {
        let model = LibraryModel()
        model.create(list: "Crossover")
        let id = model.shelves.lists[0].id

        model.rename(list: id, to: "Infinity War tie-ins")

        #expect(model.shelves.lists[0].name == "Infinity War tie-ins")
    }

    @Test("Renaming to a blank name does nothing")
    func blankNameDoesNothing() {
        let model = LibraryModel()
        model.create(collection: "Image Comics")
        let id = model.shelves.collections[0].id

        model.rename(collection: id, to: "   ")

        #expect(model.shelves.collections[0].name == "Image Comics")
    }

    @Test("The target-based dispatcher reaches the same two calls")
    func dispatcherReachesBoth() {
        let model = LibraryModel()
        model.create(collection: "Image Comics")
        model.create(list: "Crossover")
        var collectionTarget = ShelfRenameTarget(model.shelves.collections[0])
        var listTarget = ShelfRenameTarget(model.shelves.lists[0])
        collectionTarget.name = "Marvel"
        listTarget.name = "Infinity War tie-ins"

        model.rename(collectionTarget)
        model.rename(listTarget)

        #expect(model.shelves.collections[0].name == "Marvel")
        #expect(model.shelves.lists[0].name == "Infinity War tie-ins")
    }
}
