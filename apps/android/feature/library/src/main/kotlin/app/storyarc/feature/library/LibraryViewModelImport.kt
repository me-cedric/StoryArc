package app.storyarc.feature.library

/**
 * What the view model re-reads when a library import has written its stores.
 *
 * `library-portability` / *Import merges*. The import writes the source registry and the shelves
 * to their stores, and the view model holds copies in memory: without this, the reader would not
 * see an imported library until the next launch. Kept out of [LibraryViewModel] itself, which is
 * already over the line cap. iOS's `LibraryModel.reloadAfterImport` is the same step.
 */
fun LibraryViewModel.reloadAfterImport() {
    sourceStore?.let { _registry.value = it.registry() }
    shelvesStore?.let { _shelves.value = it.shelves() }
    refreshProgress()
}
