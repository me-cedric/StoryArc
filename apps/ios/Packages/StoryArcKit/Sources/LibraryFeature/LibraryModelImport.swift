public import Foundation

/// What the model re-reads when a library import has written its stores.
///
/// `library-portability` / *Import merges*. The import writes the source registry and the shelves
/// to disk, and the model holds copies in memory: without this, the reader would not see an
/// imported library until the next launch. Kept in its own file so `LibraryModel.swift` does not
/// grow. Android's `LibraryViewModel.reloadAfterImport` is the same step.
extension LibraryModel {

    /// Re-reads the sources and the shelves from their stores, then the reading positions.
    public func reloadAfterImport() async {
        if let sourceStore { registry = sourceStore.registry() }
        if let shelvesStore { shelves = shelvesStore.shelves() }
        await refreshProgress()
    }
}
