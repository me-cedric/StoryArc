public import Foundation
internal import StoryArcCore

/// What the model re-reads when a library import has written its stores.
///
/// `library-portability` / *Import merges*. The import writes the source registry and the shelves
/// to disk, and the model holds copies in memory: without this, the reader would not see an
/// imported library until the next launch. Kept in its own file so `LibraryModel.swift` does not
/// grow. Android's `LibraryViewModel.reloadAfterImport` is the same step.
extension LibraryModel {

    /// Re-reads the sources and the shelves from their stores, then the reading positions.
    ///
    /// `library-sync` task 5.7: a connection state is never stored, so a source read back
    /// from disk is *connecting*. A source the model already holds keeps the state its last
    /// probe gave, so a sync does not turn every answered library back to *connecting*.
    public func reloadAfterImport() async {
        if let sourceStore {
            let held = registry
            let stored = sourceStore.registry()
            registry = SourceRegistry(
                sources: stored.sources.map { source in
                    var kept = source
                    kept.state = held[source.id]?.state ?? source.state
                    return kept
                },
                tombstones: stored.tombstones
            )
        }
        if let shelvesStore { shelves = shelvesStore.shelves() }
        await refreshProgress()
    }
}
