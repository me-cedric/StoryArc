package app.storyarc.feature.epubreader

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import kotlin.math.abs

// The page a turn across a chapter end arrives at, rastered before the navigator moves.
//
// Task 4.3b of `reader-theming-and-page-transitions`, owner answer O14. Measured on the
// storyarc-ci emulator at 60 Hz on 2026-10-07: a turn inside a chapter took 143 to 154 ms to
// report where it landed, and a turn across a chapter end 213 to 243 ms, about 75 ms more. The
// fold stays flat until the arriving page is rastered, so that gap is a stall at the one turn
// in every chapter that crosses one. Route 1 takes the stall away at that turn: Readium keeps
// the neighbouring chapter laid out beside the current one in its `ViewPager`, so the page a
// chapter-end turn arrives at is already drawn there. Rastering it first costs no navigator
// round trip and writes no position. iOS's `ProsePages.ahead` is the twin.
//
// ponytail: this reads Readium's view structure, not its API, as `ProsePages` does on iOS. The
// pager is `internal` to the navigator, so it is found by class name. When a Readium upgrade
// moves the structure [raster] answers null and the curl waits for the navigator, which is a
// stall at a chapter end and never a wrong page.
internal object ProseAhead {

    /**
     * The neighbour a turn in screen direction [step] arrives at, drawn where the current page
     * stands, on a bitmap the size of [leaving].
     *
     * @param book the navigator's own view, which holds the pager.
     * @param step +1 for a turn to the page on the right, -1 for the page on the left.
     * @param leaving the page that is leaving, rastered from [book]. The bands outside the
     *   neighbour's own bounds are taken from it, so the colour round a short page is the one
     *   the reader already sees and not black.
     * @return null where the turn stays inside the resource, Readium holds no neighbour, or the
     *   neighbour does not show the page next to this one.
     */
    fun raster(book: ViewGroup, step: Int, leaving: Bitmap): Bitmap? {
        val pager = pagerIn(book) ?: return null
        val current = pageNearest(pager, pager.scrollX, skipping = null) ?: return null
        val web = webIn(current) ?: return null
        if (web.canScrollHorizontally(step)) return null
        val neighbour = pageNearest(pager, current.left + step * current.width, skipping = current)
            ?: return null
        // The turn arrives at the neighbour's page next to this one. Readium scrolls a neighbour
        // there only once it is current, so one loaded fresh before this page, or left mid-way
        // by a jump, shows another page. Then the curl waits for the navigator.
        if (webIn(neighbour)?.canScrollHorizontally(-step) != false) return null
        val page = Rect(0, 0, current.width, current.height)
        book.offsetDescendantRectToMyCoords(current, page)
        val picture = leaving.copy(Bitmap.Config.ARGB_8888, true) ?: return null
        val canvas = Canvas(picture)
        canvas.translate(page.left.toFloat(), page.top.toFloat())
        // A view is clipped by its parent, not by its own draw, and the neighbour's bounds are
        // what keeps it off the bands that belong to the leaving page.
        canvas.clipRect(0, 0, neighbour.width, neighbour.height)
        neighbour.draw(canvas)
        return picture
    }

    /**
     * Where the book's view stands: the pager's offset and the current page's own scroll, as one
     * number, or null where there is no pager. It differs from an earlier reading once the page
     * has turned, which Readium reports a good deal later.
     */
    fun place(book: ViewGroup): Long? {
        val pager = pagerIn(book) ?: return null
        val web = pageNearest(pager, pager.scrollX, skipping = null)?.let(::webIn)
        return pager.scrollX.toLong() * SHIFT + (web?.scrollX ?: 0)
    }

    /** The first pager under [root]: the view Readium puts its resources in. */
    fun pagerIn(root: View): ViewGroup? {
        if (root !is ViewGroup) return null
        if (isPager(root)) return root
        for (index in 0 until root.childCount) pagerIn(root.getChildAt(index))?.let { return it }
        return null
    }

    private fun isPager(view: View): Boolean {
        var type: Class<*>? = view.javaClass
        while (type != null) {
            if (type.simpleName == "ViewPager") return true
            type = type.superclass
        }
        return false
    }

    /**
     * The page whose left edge is nearest [x], within half a page. A pager lays its pages out
     * side by side, with a margin between them that this need not know.
     */
    fun pageNearest(pager: ViewGroup, x: Int, skipping: View?): View? {
        var best: View? = null
        for (index in 0 until pager.childCount) {
            val page = pager.getChildAt(index)
            if (page === skipping || page.width <= 0) continue
            val gap = abs(page.left - x)
            if (gap * 2 >= page.width) continue
            if (best == null || gap < abs(best.left - x)) best = page
        }
        return best
    }

    private fun webIn(view: View): WebView? {
        if (view is WebView) return view
        if (view !is ViewGroup) return null
        for (index in 0 until view.childCount) webIn(view.getChildAt(index))?.let { return it }
        return null
    }

    private const val SHIFT = 1L shl 20

    /** A forward turn shows the page on the right in a left-to-right book, and on the left in a right-to-left one. */
    fun step(forward: Boolean, isRightToLeft: Boolean): Int = if (forward != isRightToLeft) 1 else -1
}
