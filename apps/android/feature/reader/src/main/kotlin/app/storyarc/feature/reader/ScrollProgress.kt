package app.storyarc.feature.reader

import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
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
 * Restores the last session's fraction through [page], shown at display position
 * [target], once. Does nothing outside Scroll, with nothing stored for that page, or
 * once the reader has already moved on.
 *
 * Waits for the page to decode first: until then its item is a placeholder whose length
 * is a guess, and a fraction of the guess is not where the reader was. Then two frames,
 * so the item has been laid out at the decoded page's own length before it is read back.
 */
internal suspend fun restoreScrollFraction(paging: Paging, target: Int, page: Int, viewModel: ReaderViewModel) {
    if (paging !is Paging.Scrolled) return
    snapshotFlow { viewModel.decoded.containsKey(page) }.first { it }
    repeat(2) { withFrameNanos { } }
    val fraction = viewModel.takeScrollRestore(page)
    if (fraction == null || fraction <= 0f || paging.current != target) return
    val item = target + paging.lead
    val size = paging.state.layoutInfo.visibleItemsInfo
        .firstOrNull { it.index == item }
        ?.size
        ?: return
    paging.state.scrollToItem(item, ScrollProgress.offsetPixels(fraction, size))
}

/**
 * Reports where a continuous scroll sits within its first visible item, as it moves, with
 * that item's display position. Does nothing outside Scroll — the other containers have
 * no sub-page position to lose.
 */
internal suspend fun observeScrollFraction(paging: Paging, onFraction: (display: Int, fraction: Float) -> Unit) {
    if (paging !is Paging.Scrolled) return
    snapshotFlow {
        val index = paging.state.firstVisibleItemIndex
        val size = paging.state.layoutInfo.visibleItemsInfo
            .firstOrNull { it.index == index }
            ?.size
            ?: 0
        paging.current to ScrollProgress.fraction(paging.state.firstVisibleItemScrollOffset, size)
    }
        .distinctUntilChanged()
        .collect { (display, fraction) -> onFraction(display, fraction) }
}
