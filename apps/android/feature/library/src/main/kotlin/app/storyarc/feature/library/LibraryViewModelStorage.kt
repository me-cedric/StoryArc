package app.storyarc.feature.library

/**
 * What the cover cache alone is holding, for the storage view.
 *
 * `offline-downloads` asks for "the cover cache size" beside the downloads total, which
 * is not Settings' general cache row -- that walks the whole cache directory, the web
 * view's own data included. Kept out of [LibraryViewModel] itself, which is already over
 * the line cap.
 */
fun LibraryViewModel.coverCacheBytes(): Long = coverCache.sizeOnDisk()
