package app.storyarc.feature.reader

import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlin.math.roundToInt

/**
 * Where a continuous scroll sits within its current page, and the pixel offset that
 * returns to it.
 *
 * `comic-reader` requires the scroll position "preserved exactly" across a reopen,
 * which a page index alone cannot do for a page many screens tall. A plain object, so
 * `ScrollProgressTest` can drive it with plain numbers — the same reason
 * `EarlyPageTallness` is split out. iOS's `ScrollProgressTests` asserts the same table,
 * from a `CGRect` rather than a pixel offset and size — `LazyListState` already reports
 * both directly, so nothing here needs a geometry reader.
 */
internal object ScrollProgress {
    /** How far into a page of [pageSizePx] the reader has scrolled, from its own
     * [offsetPx]. */
    fun fraction(offsetPx: Int, pageSizePx: Int): Float {
        if (pageSizePx <= 0) return 0f
        return (offsetPx.toFloat() / pageSizePx).coerceIn(0f, 1f)
    }

    /** The pixel offset that reopens at [fraction] through a page of [pageSizePx]. */
    fun offsetPixels(fraction: Float, pageSizePx: Int): Int =
        (fraction.coerceIn(0f, 1f) * pageSizePx).roundToInt()
}

/**
 * Restores [fraction] through the page at [target], once the container has laid it out
 * enough to know its size. Does nothing outside Scroll, or with nothing stored.
 *
 * Reads the size back from the state's own layout info right after the plain jump
 * `paging.goTo` already did — `LazyListState.scrollToItem` returns only once that scroll
 * has actually applied, so the size is the real one and not a guess.
 */
internal suspend fun restoreScrollFraction(paging: Paging, target: Int, fraction: Float) {
    if (paging !is Paging.Scrolled || fraction <= 0f) return
    val size = paging.state.layoutInfo.visibleItemsInfo
        .firstOrNull { it.index == target }
        ?.size
        ?: return
    paging.state.scrollToItem(target, ScrollProgress.offsetPixels(fraction, size))
}

/**
 * Remembers where a continuous scroll sits within its current page, as it moves. Does
 * nothing outside Scroll — the other containers have no sub-page position to lose.
 */
internal suspend fun observeScrollFraction(paging: Paging, onFraction: (Float) -> Unit) {
    if (paging !is Paging.Scrolled) return
    snapshotFlow {
        val index = paging.state.firstVisibleItemIndex
        val size = paging.state.layoutInfo.visibleItemsInfo
            .firstOrNull { it.index == index }
            ?.size
            ?: 0
        ScrollProgress.fraction(paging.state.firstVisibleItemScrollOffset, size)
    }
        .distinctUntilChanged()
        .collect(onFraction)
}
