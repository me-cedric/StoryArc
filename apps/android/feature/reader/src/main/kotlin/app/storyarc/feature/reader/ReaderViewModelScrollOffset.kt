package app.storyarc.feature.reader

/**
 * Where a continuous scroll should reopen, and where it leaves off. Split out of
 * `ReaderViewModel` itself, which is at its line cap.
 */

/**
 * The fraction through the current page a continuous scroll last stopped at, or 0 when
 * none was ever stored — which reopens at the page's own top, exactly as today.
 */
internal fun ReaderViewModel.restoredScrollFraction(): Float =
    shelfStore?.scrollOffsets()?.fraction(publication.identity) ?: 0f

/**
 * Remembers where a continuous scroll sits within the current page.
 *
 * Local only — see `ScrollOffsetMemory` for why this does not touch `ReadingProgress`,
 * which is what `record` writes and what syncs.
 */
internal fun ReaderViewModel.saveScrollFraction(fraction: Float) {
    val store = shelfStore ?: return
    store.save(store.scrollOffsets().remembering(publication.identity, fraction))
}
