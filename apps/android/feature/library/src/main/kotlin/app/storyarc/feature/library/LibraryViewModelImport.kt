package app.storyarc.feature.library

/**
 * What the view model re-reads when a library import has written its stores.
 *
 * `library-portability` / *Import merges*. The import writes the source registry and the shelves
 * to their stores, and the view model holds copies in memory: without this, the reader would not
 * see an imported library until the next launch. Kept out of [LibraryViewModel] itself, which is
 * already over the line cap. iOS's `LibraryModel.reloadAfterImport` is the same step.
 *
 * `library-sync` task 5.7: a connection state is never stored, so a source read back from disk
 * is *connecting*. A source the view model already holds keeps the state its last probe gave,
 * so a sync does not turn every answered library back to *connecting*.
 */
fun LibraryViewModel.reloadAfterImport() {
    sourceStore?.let { store ->
        val held = _registry.value
        val stored = store.registry()
        _registry.value = stored.copy(
            sources = stored.sources.map { source -> held[source.id]?.let { source.copy(state = it.state) } ?: source },
        )
    }
    shelvesStore?.let { _shelves.value = it.shelves() }
    refreshProgress()
}
