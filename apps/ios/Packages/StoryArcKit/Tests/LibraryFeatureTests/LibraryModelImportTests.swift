import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// `library-portability` / *Import merges*: an import writes the stores, and the model that holds
/// copies of two of them re-reads them. Without this a reader sees an imported library only after
/// the next launch. Android's `ReloadAfterImportTest` asserts the same row.
@Suite("The library model reloads what an import wrote")
@MainActor
struct LibraryModelImportTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test("The sources and the shelves an import wrote appear, and what was there stays")
    func reloadReadsTheStores() async {
        let defaults = defaults()
        let sourceStore = SourceStore(defaults: defaults)
        let shelvesStore = ShelvesStore(defaults: defaults)
        let model = LibraryModel(sourceStore: sourceStore, shelvesStore: shelvesStore)
        #expect(model.registry.sources.isEmpty)
        #expect(model.shelves.collections.isEmpty)

        // What `LibraryArchive.apply` does to the two stores.
        sourceStore.save(SourceRegistry(sources: [
            Source(displayName: "Comics NAS", kind: .networkShare, locator: "smb://nas.local/comics"),
        ]))
        shelvesStore.save(Shelves(collections: [PublicationCollection(name: "Image Comics")]))
        #expect(model.registry.sources.isEmpty)

        await model.reloadAfterImport()

        #expect(model.registry.sources.map(\.displayName) == ["Comics NAS"])
        #expect(model.shelves.collections.map(\.name) == ["Image Comics"])
    }

    @Test("A model with no stores is left as it is")
    func noStoresNoChange() async {
        let model = LibraryModel()

        await model.reloadAfterImport()

        #expect(model.registry.sources.isEmpty)
        #expect(model.shelves.collections.isEmpty)
    }
}
