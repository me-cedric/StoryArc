package app.storyarc.feature.epubreader

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import kotlin.coroutines.resume
import kotlin.math.abs
import kotlinx.coroutines.suspendCancellableCoroutine

// Taking the page turn over from Readium, so a transition StoryArc draws can run over
// reflowable text.
//
// `page-transitions` offers four modes and an EPUB could only ever do two of them. The
// reason was never the shader: it is that Readium owns the turn. Slide is Readium's own
// paginated pager, and nothing in StoryArc was ever holding a turn between two pages.
//
// This is the Android half of what `EpubReaderModel.turnWithFade(forward:)` does on iOS:
// one dip through the page colour, which is Fast fade. Curl needs the *incoming* page as
// a second texture before it is on screen, and that is a separate problem on both.
//
// The two platforms take the turn over differently, and the difference is deliberate.
// iOS has to disable Readium's paginated scroll and then put back the swipe it just took
// away, because that scroll view is what animates a Slide. Android's pager only turns a
// page once a horizontal drag has passed the touch slop, and a parent can intercept
// exactly that and nothing else — so taps never leave the web view, and links, text
// selection and Readium's own input listener go on working while Fast fade is chosen.

/**
 * Which way a finished drag meant to turn, or `null` when it meant nothing.
 *
 * Pulled out of the view so it can be tested without a touch screen: this is the whole
 * rule, and the rest of [TurnInterceptor] is Android's dispatch contract.
 */
internal object TurnDrag {

    /**
     * Enough travel to mean a turn rather than a stray finger.
     *
     * The same 40 the iOS half uses, read there as points and here as dp — which is the
     * same distance under a reader's thumb, and not the same number of pixels.
     */
    const val THRESHOLD_DP: Float = 40f

    /**
     * `true` to go forward, `false` to go back, `null` to leave the page alone.
     *
     * Dragging leftwards moves forwards, the way every paginated reader behaves. The
     * threshold is exclusive: a drag of exactly the threshold has not passed it.
     */
    fun direction(travel: Float, threshold: Float): Boolean? =
        if (abs(travel) <= threshold) null else travel < 0
}

/**
 * The navigator's parent while StoryArc owns the turn.
 *
 * Wrapping the fragment container rather than sitting over it: a sibling laid on top
 * would have to decide at `ACTION_DOWN` whether the gesture will become a drag, which is
 * the one moment nothing can know that yet. A parent decides later, when the finger has
 * actually moved, which is also when Readium's pager would have decided.
 *
 * [onTurn] is `null` while Readium owns the turn, and then this view never intercepts
 * anything and the reader gets Readium's own Slide. Only Fast fade sets it.
 */
internal class TurnInterceptor(context: Context) : FrameLayout(context) {

    var onTurn: ((Boolean) -> Unit)? = null

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private val threshold = THRESHOLD_DP_PX(context)
    private var downX = 0f
    private var isOwningGesture = false

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (onTurn == null) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                isOwningGesture = false
            }
            MotionEvent.ACTION_MOVE ->
                // Past the slop and this is a drag, not a tap. Taking it here is what
                // stops the pager taking it, and taking it no earlier is what leaves a
                // tap on a link to the web view.
                if (abs(event.x - downX) > slop) isOwningGesture = true
        }
        return isOwningGesture
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val turn = onTurn ?: return false
        when (event.actionMasked) {
            // Only reached when this view was the one touched — the container fills it,
            // so in practice the intercept above is the way in.
            MotionEvent.ACTION_DOWN -> downX = event.x
            MotionEvent.ACTION_UP ->
                TurnDrag.direction(event.x - downX, threshold)?.let(turn)
        }
        return true
    }

    @Suppress("FunctionName")
    private companion object {
        fun THRESHOLD_DP_PX(context: Context): Float =
            TurnDrag.THRESHOLD_DP * context.resources.displayMetrics.density
    }
}

/**
 * A page turn drawn as a dip through the page's own colour.
 *
 * Not a cross-fade. Two pages of body text do not share a baseline grid, so dissolving
 * one into the other shows every line twice, half-offset — which reads as doubled text
 * rather than as a fade. Fading out to the page colour and back in from it never shows
 * both at once. The iOS half carries the same note for the same reason.
 *
 * The move happens at the peak, while the dip is fully opaque, so nothing has to be
 * rasterised first. iOS takes a snapshot instead and moves under it, because there the
 * navigator's own move is `async` and overlapping it with the fade is what keeps the turn
 * feeling immediate; here the pager's neighbouring page is already laid out and
 * `goForward(animated = false)` returns before the next frame, so there is nothing to
 * overlap and nothing to snapshot.
 */
internal class FadeTurn(private val host: ViewGroup, private val index: Int) {

    /**
     * Turns, and reports whether the page actually changed.
     *
     * [move] is called once, at the moment the dip is opaque. When it says the book did
     * not move — the last page, the first page — the dip comes straight back off rather
     * than completing, because a full fade there would look like a turn that happened.
     */
    suspend fun run(pageColour: Int, move: () -> Boolean): Boolean {
        val dip = View(host.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(pageColour)
            alpha = 0f
            isClickable = false
            isFocusable = false
        }
        host.addView(dip, index)
        try {
            dip.animateAlpha(to = 1f)
            if (!move()) return false
            dip.animateAlpha(to = 0f)
            return true
        } finally {
            host.removeView(dip)
        }
    }

    /** Half the turn, so the two phases together take [DURATION_MS]. */
    private suspend fun View.animateAlpha(to: Float) =
        suspendCancellableCoroutine { continuation ->
            val animation = animate()
                .alpha(to)
                .setDuration(DURATION_MS / 2)
                .setListener(
                    object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            if (!continuation.isCompleted) continuation.resume(Unit)
                        }
                    },
                )
            animation.start()
            continuation.invokeOnCancellation { animate().cancel() }
        }

    internal companion object {
        /**
         * Short enough not to read as an animation, which is the point of the name.
         *
         * The 240ms iOS settled on, for the same reason it settled on it: this is two
         * phases rather than one, and half of 180ms each was too quick to read as
         * anything but a flicker.
         */
        const val DURATION_MS: Long = 240
    }
}
