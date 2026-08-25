package app.storyarc.feature.reader

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.isScroll

/**
 * Where the reader is, and how it gets somewhere else.
 *
 * `page-transitions` calls this the transition coordinator, and this is the shape it
 * takes here. Slide is a pager, Fast fade is one page at a time, and Scroll is a lazy
 * list. All three answer the same two questions, and nothing above them — the chrome,
 * the page slider, the thumbnail strip, the end screen — should have to know which
 * one is underneath. Before this, fourteen call sites reached into a `PagerState`.
 *
 * Positions here are *display* positions, not page numbers. Right-to-left reverses
 * the display order, and the mapping stays where it already was, in the screen.
 */
internal sealed interface Paging {
    /** The display position now showing. */
    val current: Int

    /** Moves there. Animated where the mode animates and instant where it does not. */
    suspend fun goTo(display: Int, animate: Boolean = true)

    /** Slide: a pager, which brings its own gesture, fling and edge resistance. */
    class Paged(val state: PagerState) : Paging {
        override val current get() = state.currentPage
        override suspend fun goTo(display: Int, animate: Boolean) {
            if (animate) state.animateScrollToPage(display) else state.scrollToPage(display)
        }
    }

    /**
     * Fast fade and Curl: no container at all, just an index.
     *
     * Both modes draw one page at a time and own their own animation, so there is
     * nothing to scroll and nothing to hold a scroll position. A `PagerState` was used
     * for the curl first and quietly refused to move: a pager state with no pager laid
     * out has nothing to scroll either, and asking it to animate does nothing at all.
     */
    class Indexed(val index: MutableIntState) : Paging {
        override val current get() = index.intValue
        override suspend fun goTo(display: Int, animate: Boolean) {
            index.intValue = display
        }
    }

    /**
     * Scroll: a lazy list, stitched with no gap.
     *
     * `current` is the first visible item rather than the nearest one. In a
     * continuous scroll the page you are reading is the one you have reached, and
     * rounding to the nearest would make the counter jump forward before the page
     * does.
     */
    class Scrolled(val state: LazyListState) : Paging {
        override val current get() = state.firstVisibleItemIndex
        override suspend fun goTo(display: Int, animate: Boolean) {
            if (animate) state.animateScrollToItem(display) else state.scrollToItem(display)
        }
    }
}

/**
 * The coordinator for one mode, seeded from where the reader already is.
 *
 * Keyed on the mode, so switching rebuilds the state — and seeded from the position
 * passed in, because `page-transitions` requires a mode change to apply "immediately
 * without losing the reading position". A fresh state defaulting to zero would send
 * the reader back to page one for choosing a different animation.
 */
@Composable
internal fun rememberPaging(mode: PageTransition, count: Int, position: Int): Paging = when {
    mode.isScroll -> {
        val state = rememberLazyListState(initialFirstVisibleItemIndex = position)
        // Remembered, not rebuilt. A fresh wrapper on every recomposition is a fresh
        // `LaunchedEffect` key, and an effect that writes the position it just read
        // then recomposes for ever — which looks exactly like a reader whose taps do
        // nothing, because the frame never settles.
        remember(state) { Paging.Scrolled(state) }
    }
    // Both container-less modes. Curl animates its own fold and Fast fade its own
    // dissolve; neither has anything for a scroll state to describe.
    mode == PageTransition.FAST_FADE || mode == PageTransition.PAGE_CURL -> {
        val index = remember(mode) { mutableIntStateOf(position) }
        remember(index) { Paging.Indexed(index) }
    }
    else -> {
        val state = rememberPagerState(initialPage = position, pageCount = { count })
        remember(state) { Paging.Paged(state) }
    }
}
