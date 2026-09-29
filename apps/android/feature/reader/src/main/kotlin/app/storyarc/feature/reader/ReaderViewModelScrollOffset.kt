package app.storyarc.feature.reader

/**
 * Where a continuous scroll should reopen, and where it leaves off. Split out of
 * `ReaderViewModel` itself, which is at its line cap.
 *
 * `pendingScrollRestore` is read from the store when the model is built, so the first
 * save of this session cannot overwrite what the last one left before the restore has
 * read it. The scroll saves on its very first layout, before it has restored anything.
 */

/**
 * The fraction through [page] that the last session's scroll stopped at, handed over
 * once. `null` when it stopped on another page, or never stopped at all.
 */
internal fun ReaderViewModel.takeScrollRestore(page: Int): Float? {
    val entry = pendingScrollRestore
    pendingScrollRestore = null
    return entry?.takeIf { it.page == page }?.fraction
}

/**
 * Remembers where a continuous scroll sits within [page].
 *
 * Local only — see `ScrollOffsetMemory` for why this does not touch `ReadingProgress`,
 * which is what `record` writes and what syncs.
 */
internal fun ReaderViewModel.saveScrollFraction(fraction: Float, page: Int) {
    val store = shelfStore ?: return
    store.save(store.scrollOffsets().remembering(publication.identity, fraction, page))
}
