package app.storyarc.feature.epubreader

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.TransitionChoices
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

/**
 * Whether Fast fade draws the turn rather than Readium: `effective`, not the chosen mode.
 * Under Reduce Motion a chosen Slide runs as Fast fade, and the turn has to follow it --
 * it stayed Readium's animated Slide while this read the chosen mode.
 */
internal val TransitionChoices.fadeOwnsTheTurn: Boolean
    get() = effective == PageTransition.FAST_FADE

/**
 * Where a tap lands, by edge band. `page-transitions`: edge-third taps turn the page
 * "where enabled in settings", in every mode -- not only while Fast fade owns the turn,
 * which is the one case [TurnInterceptor] above already handled.
 */
internal object EdgeTap {
    /** A third of the width, the same band the comic reader's `EDGE_ZONE_FRACTION` is. */
    const val EDGE_FRACTION = 1f / 3f

    /**
     * `true` to turn forward, `false` back, `null` to reveal the chrome instead --
     * either because the tap landed in the middle third, or because the setting is off.
     */
    fun outcome(x: Float, width: Float, tapTurnsPages: Boolean): Boolean? {
        if (!tapTurnsPages) return null
        val band = width * EDGE_FRACTION
        return when {
            x < band -> false
            x > width - band -> true
            else -> null
        }
    }
}

/**
 * Which action, if any, a key press means for the reflowable reader. Arrow, page and
 * space keys turn the page; Enter toggles the chrome, the same as the comic reader's own
 * `ReaderKeyAction` -- a separate type because `feature:epubreader` cannot depend on
 * `feature:reader` for it ("no feature depends on another feature module").
 */
internal enum class EpubTurnKey {
    TurnBackward, TurnForward, ToggleChrome,
    ;

    companion object {
        fun of(keyCode: Int): EpubTurnKey? = when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_PAGE_UP -> TurnBackward
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_PAGE_DOWN, KeyEvent.KEYCODE_SPACE -> TurnForward
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> ToggleChrome
            else -> null
        }
    }
}

/**
 * Whether a volume key turns the page, and which way. `page-transitions`: "the volume
 * buttons turn pages where enabled in settings"; volume-down is documented as always
 * forward, the same convention `MainActivity.onKeyDown` uses for the comic reader.
 */
internal fun volumeTurnsForward(keyCode: Int): Boolean? = when (keyCode) {
    KeyEvent.KEYCODE_VOLUME_DOWN -> true
    KeyEvent.KEYCODE_VOLUME_UP -> false
    else -> null
}
