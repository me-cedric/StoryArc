package app.storyarc.feature.epubreader

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Build
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import androidx.core.graphics.createBitmap
import app.storyarc.core.model.PageCurl
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.TransitionChoices
import kotlin.coroutines.resume
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

// The curl over reflowable text, which is task 4.3b of `reader-theming-and-page-transitions`.
//
// `ReflowableTurn.kt` took the turn over from Readium and spent it on no raster at all: the
// dip is opaque at the moment the pager moves, so Fast fade never needed a picture. This does.
// The shader is the comic reader's, unchanged -- `PageCurl` and `PageRoll` both live in
// `:core:model` so that neither reader owns them -- so a reader who turns a page of prose and
// a reader who turns a page of a comic watch the same sheet roll.
//
// **What is rolled is a picture, and only while the turn runs.** `ebook-reader` keeps a
// reflowable page as live web content: text is selectable, links are followable, and a
// read-aloud voice walks the DOM. None of that survives a texture, so the texture exists for
// the length of one turn and the live page is underneath it the whole time.

/**
 * This view as it is drawn, at the display's own scale.
 *
 * A view's own width and height are already pixels, so a bitmap of that size is the page at
 * one texture pixel per display pixel -- which `page-transitions` asks for by name, and which
 * body text is the one content where the difference is unmistakable.
 *
 * ponytail: `draw(Canvas)` rather than `PixelCopy`. `PixelCopy` reads the window, and by the
 * time the incoming page is photographed the sheet is already over it -- so the window holds
 * the picture this is trying to take. Drawing one view draws that view. The ceiling is that a
 * hardware-only layer inside the web view can come back blank; every caller here reads a null
 * or an unusable raster as "no curl this time", which costs a transition and never a turn.
 */
internal fun View.raster(): Bitmap? {
    if (width <= 0 || height <= 0) return null
    val bitmap = createBitmap(width, height)
    draw(Canvas(bitmap))
    return bitmap
}

/**
 * The rolling sheet, drawn over the book while a turn runs.
 *
 * A plain [View] rather than a Compose island: this goes into the same `FrameLayout` the Fast
 * fade dip goes into, at the same index, and a `ComposeView` raised and torn down per turn
 * would cost a composition for one rectangle filled with a shader.
 *
 * The shader is parsed once, in the constructor, for the reason `CurledPages` parses it once:
 * `RuntimeShader(source)` compiles the whole AGSL program, which is cheap once and wasteful on
 * every frame of every turn.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
internal class CurlSheet(context: Context) : View(context) {

    private val shader = PageCurl.newShader()
    private val paint = Paint()

    /** The page being turned away, rastered before the pager moved. */
    var page: Bitmap? = null

    /** The page underneath it, rastered after the pager moved and before this was shown. */
    var beneath: Bitmap? = null

    var isRightToLeft: Boolean = false

    /** Where the roll stands: 0 for a flat page, 1 for a whole turn. */
    var progress: Float = 0f
        set(value) {
            field = value
            invalidate()
        }

    init {
        // The sheet is a picture of the page. A reader touching it would be touching a
        // photograph, and the live page is one frame away underneath.
        isClickable = false
        isFocusable = false
    }

    override fun onDraw(canvas: Canvas) {
        val turning = page ?: return
        PageCurl.update(
            shader,
            width = width.toFloat(),
            height = height.toFloat(),
            progress = progress,
            isRightToLeft = isRightToLeft,
            page = turning,
            beneath = beneath,
        )
        paint.shader = shader
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }
}

/**
 * A page turn drawn as one sheet rolling off the next.
 *
 * The order is the whole trick, and it is one pager move rather than three:
 *
 * 1. the outgoing page is rastered while it is still the only thing on screen;
 * 2. the sheet goes up at a progress of zero, where the shader draws that raster flat and
 *    whole -- so the sheet is indistinguishable from the page under it;
 * 3. the pager moves with no animation of its own, hidden under the sheet;
 * 4. the page that arrived is rastered and becomes the sheet beneath;
 * 5. the roll runs, and the sheet comes off, leaving the live page it was hiding.
 *
 * iOS's `ReflowableCurl.swift` runs the same five steps in the same order.
 *
 * @param host what the sheet is added to, above the book and below the chrome.
 * @param index where in [host] the sheet goes, which is where the dip goes.
 * @param book the view the two rasters are taken of. Not [host]: the sheet is in [host] by
 *   step 4, and a raster of [host] would then photograph the sheet rather than the page.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
internal class ProseCurl(
    private val host: ViewGroup,
    private val index: Int,
    private val book: View,
) {

    /**
     * Turns, and reports whether the page actually changed.
     *
     * [move] is called once, under the sheet. When it says the book did not move -- the last
     * page, the first page -- the sheet comes straight back off rather than rolling, because a
     * roll onto the page it started from reads as a turn that did happen.
     *
     * A raster that does not arrive leaves the turn as a cut: by then the pager has moved, so
     * the reader loses the transition and never the page.
     */
    suspend fun run(isRightToLeft: Boolean, move: suspend () -> Boolean): Boolean {
        val outgoing = book.raster() ?: return move()

        val sheet = CurlSheet(host.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            page = outgoing
            // Stood in by the outgoing page until step 4 has one. The shader samples the
            // sheet beneath only past the fold, and at a progress of zero there is no past
            // the fold.
            beneath = outgoing
            this.isRightToLeft = isRightToLeft
        }
        host.addView(sheet, index)
        try {
            if (!move()) return false
            // Two frames: one for the moved page to lay out, one for it to draw. A raster
            // taken sooner photographs the page the reader is leaving.
            book.nextFrame()
            book.nextFrame()
            sheet.beneath = book.raster() ?: return true
            sheet.roll()
            return true
        } finally {
            host.removeView(sheet)
        }
    }

    private suspend fun View.nextFrame() =
        suspendCancellableCoroutine { continuation -> postOnAnimation { continuation.resume(Unit) } }

    /** Runs the roll and returns when it has finished. */
    private suspend fun CurlSheet.roll() = suspendCancellableCoroutine { continuation ->
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = DURATION_MS
            addUpdateListener { progress = it.animatedValue as Float }
            addListener(
                object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        if (!continuation.isCompleted) continuation.resume(Unit)
                    }
                },
            )
        }
        animator.start()
        continuation.invokeOnCancellation { animator.cancel() }
    }

    internal companion object {
        /**
         * How long one roll takes.
         *
         * Longer than [FadeTurn.DURATION_MS], and deliberately: a dip is meant not to read as
         * an animation, and a roll is the one transition a reader chooses *because* they want
         * to watch it. iOS's `EpubReaderModel.curlDuration` is the same number in seconds.
         */
        const val DURATION_MS: Long = 340
    }
}

/**
 * The transition this reader draws itself, or null where Readium keeps the turn.
 *
 * `effective`, not the chosen mode: under Reduce Motion a chosen Slide runs as Fast fade, and
 * the turn has to follow that. Two modes answer now -- Fast fade, whose dip needs no picture
 * at all, and Curl, which needs two. iOS's `EpubReaderModel.drawnTurn` is the twin.
 */
internal val TransitionChoices.drawnTurn: PageTransition?
    get() = when (effective) {
        PageTransition.FAST_FADE -> PageTransition.FAST_FADE
        PageTransition.PAGE_CURL -> PageTransition.PAGE_CURL
        else -> null
    }

/**
 * Which page-turn rows to offer, and which of them this content cannot run.
 *
 * Beside the turns it decides rather than on the view model, which is at the line cap
 * `scripts/line-cap.mjs` holds. That is the better place for it anyway: this file already
 * holds [drawnTurn], which reads nothing else, and a reader of either has to read both.
 *
 * [reduceMotion] is a parameter rather than read here, so a recomposition on the reader's
 * `reduceMotionFlow` recomputes this too.
 */
internal fun EpubReaderViewModel.transitions(reduceMotion: Boolean): TransitionChoices =
    TransitionChoices(
        chosen = transition.value,
        // Reflowing text scrolls the way it is read; the axis is not a choice here.
        axis = ScrollAxis.VERTICAL,
        reduceMotion = reduceMotion,
        canCurl = canCurl,
        // The activity takes the turn over from Readium for both: `TurnInterceptor` steals
        // the drag, `FadeTurn` draws the dip, and `ProseCurl` rasters the page either side of
        // the move and rolls the first off the second (task 8.12). Either was false until its
        // turn existed, because offering a mode that quietly gave a Slide instead would have
        // been worse than saying it was not available yet.
        canFade = true,
        canCurlOverText = true,
        isReflowable = true,
    )

/**
 * Calls [move], then waits until [location] reports somewhere new. False when it never does
 * within [timeoutMillis].
 *
 * Readium's `goForward` answers before the page has moved -- it posts the scroll to a
 * coroutine and a JavaScript call -- and it answers true at the last page too, where nothing
 * moves at all. Its answer says nothing about whether a page turned. The location does: it
 * changes when the page does, and only then. So the curl rasters the incoming page only after
 * this, and does not roll at all where the book stood still.
 */
internal suspend fun <T> movedTo(
    location: Flow<T>,
    timeoutMillis: Long = MOVE_TIMEOUT_MILLIS,
    move: () -> Unit,
): Boolean {
    val before = location.first()
    move()
    return withTimeoutOrNull(timeoutMillis) { location.first { it != before } } != null
}

/** How long a turn may take to report a new location before it counts as no turn. */
internal const val MOVE_TIMEOUT_MILLIS = 500L
