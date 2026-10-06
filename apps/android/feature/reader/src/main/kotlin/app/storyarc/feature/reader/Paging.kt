package app.storyarc.feature.reader

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.spring
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.key
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

    /**
     * Slide: a pager, which brings its own gesture, fling and edge resistance.
     *
     * [lead] is how many pager pages come before display position 0: one under
     * right-to-left, where the end slot sits before the last page (see
     * [endSlotPosition]), and none otherwise.
     */
    class Paged(val state: PagerState, val lead: Int = 0) : Paging {
        override val current get() = state.currentPage - lead
        override suspend fun goTo(display: Int, animate: Boolean) {
            val page = display + lead
            if (animate) state.animateScrollToPage(page) else state.scrollToPage(page)
        }
    }

    /**
     * Fast fade: no container at all, just an index.
     *
     * The mode draws one page at a time and owns its own dissolve, so there is nothing to
     * scroll and nothing to hold a scroll position. A `PagerState` was used for the curl
     * first and quietly refused to move: a pager state with no pager laid out has nothing
     * to scroll either, and asking it to animate does nothing at all.
     */
    class Indexed(val index: MutableIntState) : Paging {
        override val current get() = index.intValue
        override suspend fun goTo(display: Int, animate: Boolean) {
            index.intValue = display
        }
    }

    /**
     * Curl: the same index, and the fold that runs between two of them.
     *
     * **[goTo] is the whole difference from [Indexed].** The curl keeps its motion in the
     * drag gesture, so every turn a finger did not drag — an edge tap, an arrow key, a
     * game controller, a volume button, VoiceOver's own action — set the index and the
     * next page simply appeared. `page-transitions` gives Curl one motion, and that was a
     * second one, in the mode a reader chooses *for* its fold. A move of one reading-order
     * position now runs the same spring the released drag runs (task 8.3).
     *
     * [progress] is shared with [CurledPages], which draws it and drives it from the drag.
     * The curl's own completed turn commits through `animate = false`, because the fold it
     * would otherwise start is the fold that has just finished. iOS carries the same rule
     * as `CurlRequest`, filed by `ReaderView.turnWithTransition(by:)`.
     */
    class Curled(
        val index: MutableIntState,
        val progress: Animatable<Float, AnimationVector1D>,
        private val isRightToLeft: Boolean,
    ) : Paging {
        override val current get() = index.intValue

        override suspend fun goTo(display: Int, animate: Boolean) {
            val step = curlStep(index.intValue, display, isRightToLeft, animate)
            if (step == 0) {
                index.intValue = display
                return
            }
            progress.animateTo(targetValue = step.toFloat(), animationSpec = spring())
            // The page swap first, then the reset: the other order shows the outgoing page
            // flat for a frame before it goes.
            index.intValue = display
            progress.snapTo(0f)
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
    class Scrolled(val state: LazyListState, val lead: Int = 0) : Paging {
        override val current get() = state.firstVisibleItemIndex - lead
        override suspend fun goTo(display: Int, animate: Boolean) {
            val item = display + lead
            if (animate) state.animateScrollToItem(item) else state.scrollToItem(item)
        }
    }
}

/**
 * The display position of the slot past the last page, which Slide and Scroll reach on a
 * swipe or a scroll with nothing left to turn to.
 *
 * `comic-reader`: "a swipe or a scroll past the last page reaches the end screen". Past
 * the last page *in reading order*: after the run in left-to-right, and before it under
 * right-to-left, where the display order is reversed and the last page is position 0. A
 * slot after the run there sits beyond page one, and a swipe back from page one opened
 * the end screen. iOS's `endSlotPosition` is the same rule.
 */
internal fun endSlotPosition(slotCount: Int, isRightToLeft: Boolean): Int =
    if (isRightToLeft) -1 else slotCount

/**
 * The display-order step that a reading-order turn of `step` performs.
 *
 * `comic-reader`: Space, Page Up/Down and the volume keys mean "the next page to read",
 * not "the next position on screen". Under right-to-left those differ, because the
 * display order is reversed (`slotIndex`) while the reading order is not, so the step
 * has to flip to keep meaning "next". Held outside the composable so `ReaderScreen`'s
 * own test can reach it.
 */
internal fun readingOrderStep(step: Int, isRightToLeft: Boolean): Int =
    if (isRightToLeft) -step else step

/**
 * The fold a move from [from] to [to] rolls, in reading order, or 0 to cut to the page.
 *
 * Pulled out of [Paging.Curled.goTo] so it can be asserted without a frame clock, the way
 * iOS's `CurlRequest.runsCurl` is: this is the whole rule, and the rest of `goTo` is the
 * spring.
 *
 * A move of exactly one reading-order position rolls. A jump across the publication does
 * not — it has no fold, and the slider, the thumbnail strip and the way back from a jump
 * all arrive here. Nor does a move the caller asked to make instantly, which is how the
 * curl's own completed turn commits the page it has just rolled.
 */
internal fun curlStep(from: Int, to: Int, isRightToLeft: Boolean, animate: Boolean): Int {
    if (!animate) return 0
    val step = readingOrderStep(to - from, isRightToLeft)
    return if (step == 1 || step == -1) step else 0
}

/**
 * The display position one reading-order step from [from], or null past either end of
 * the publication.
 *
 * `readingOrderStep` already carries the right-to-left mirroring a tap or a key turns
 * with; the curl's beneath and previous sheets need the same step, because "forward"
 * and "backward" mean reading order to a reader whichever way the pages are laid out on
 * screen — a raw `from + 1` is the *previous* page in reading order once right-to-left
 * has reversed the display order.
 */
internal fun adjacentDisplayIndex(
    from: Int,
    steps: Int,
    slotCount: Int,
    isRightToLeft: Boolean,
): Int? {
    val candidate = from + readingOrderStep(steps, isRightToLeft)
    return candidate.takeIf { it in 0 until slotCount }
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
internal fun rememberPaging(
    mode: PageTransition,
    count: Int,
    position: Int,
    isRightToLeft: Boolean,
): Paging = key(isRightToLeft) {
    // Keyed on the direction, because the end slot moves to the other end of the run and
    // every pager page shifts by one with it. A fresh state seeded from `position` keeps
    // the page the reader is on, the way a mode change already does.
    val lead = if (isRightToLeft) 1 else 0
    when {
        mode.isScroll -> {
            val state = rememberLazyListState(initialFirstVisibleItemIndex = position + lead)
            // Remembered, not rebuilt. A fresh wrapper on every recomposition is a fresh
            // `LaunchedEffect` key, and an effect that writes the position it just read
            // then recomposes for ever — which looks exactly like a reader whose taps do
            // nothing, because the frame never settles.
            remember(state) { Paging.Scrolled(state, lead) }
        }
        // Both container-less modes. Curl animates its own fold and Fast fade its own
        // dissolve; neither has anything for a scroll state to describe.
        mode == PageTransition.PAGE_CURL -> {
            val index = remember(mode) { mutableIntStateOf(position) }
            val progress = remember(mode) { Animatable(0f) }
            remember(index, progress) { Paging.Curled(index, progress, isRightToLeft) }
        }
        mode == PageTransition.FAST_FADE -> {
            val index = remember(mode) { mutableIntStateOf(position) }
            remember(index) { Paging.Indexed(index) }
        }
        else -> {
            // `count + 1`: one slot past the last page, for a swipe with nothing left to
            // turn to. `comic-reader`: "a swipe past the last page reaches the end
            // screen" — without it `HorizontalPager` simply resists at the last page, the
            // way it resists at the first. `ReaderScreen`'s own composable turns reaching
            // it into `hasReachedEnd`.
            val state = rememberPagerState(initialPage = position + lead, pageCount = { count + 1 })
            remember(state) { Paging.Paged(state, lead) }
        }
    }
}
