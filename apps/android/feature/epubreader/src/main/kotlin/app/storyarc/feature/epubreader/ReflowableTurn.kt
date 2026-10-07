package app.storyarc.feature.epubreader

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.TransitionChoices
import kotlin.coroutines.resume
import kotlin.math.abs
import kotlinx.coroutines.suspendCancellableCoroutine
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.preferences.ReadingProgression

// Taking the page turn over from Readium, so a transition StoryArc draws can run over
// reflowable text.
//
// `page-transitions` offers four modes and an EPUB could only ever do two of them. The
// reason was never the shader: it is that Readium owns the turn. Slide is Readium's own
// paginated pager, and nothing in StoryArc was ever holding a turn between two pages.
//
// This is the Android half of what `EpubReaderModel.turnWithFade(forward:)` does on iOS:
// one dip through the page colour, which is Fast fade. Curl takes the same drag and hands
// every phase of it to `ProseCurlDriver`, which rolls a raster of the page (`ProseCurl.kt`).
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
     * Dragging leftwards moves forwards in a left-to-right book; a right-to-left book
     * mirrors it, the same way the edge taps and the arrow keys do -- see [EdgeTap] and
     * [EpubTurnKey]. The threshold is exclusive: a drag of exactly the threshold has not
     * passed it.
     */
    fun direction(travel: Float, threshold: Float, isRightToLeft: Boolean = false): Boolean? =
        if (abs(travel) <= threshold) null else (travel < 0) != isRightToLeft
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
 * anything and the reader gets Readium's own Slide. Fast fade reads the drag once, when the
 * finger lifts. Curl sets [onDrag] as well and reads every phase, because the finger drives
 * the fold (task 8.12).
 */
internal class TurnInterceptor(context: Context) : FrameLayout(context) {

    var onTurn: ((Boolean) -> Unit)? = null

    /** Non-null while Curl owns the turn: every phase of the drag goes here. */
    var onDrag: ((ProseDrag) -> Unit)? = null

    /** Mirrors the drag, the way [EdgeTap] and [EpubTurnKey] mirror a tap and a key. */
    var isRightToLeft: () -> Boolean = { false }

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private val threshold = THRESHOLD_DP_PX(context)
    private var downX = 0f
    private var downY = 0f
    private var isOwningGesture = false
    private var velocity: VelocityTracker? = null

    /**
     * Arms the drag for the turn this reader draws: none for Readium's own, the swipe for Fast
     * fade, and the swipe and every phase of the finger for Curl. One call, because the reader
     * picks a page turn after the book is open and both have to follow it together.
     */
    fun arm(drawnTurn: PageTransition?, turns: EpubPageTurns) {
        onTurn = if (drawnTurn != null) turns::swipe else null
        onDrag = if (drawnTurn == PageTransition.PAGE_CURL) turns::drag else null
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (onTurn == null) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> pressed(event)
            MotionEvent.ACTION_MOVE -> {
                velocity?.addMovement(event)
                moved(event)
            }
        }
        return isOwningGesture
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val turn = onTurn ?: return false
        when (event.actionMasked) {
            // Only reached when this view was the one touched — the container fills it,
            // so in practice the intercept above is the way in.
            MotionEvent.ACTION_DOWN -> pressed(event)
            MotionEvent.ACTION_MOVE -> {
                velocity?.addMovement(event)
                moved(event)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                velocity?.addMovement(event)
                released(event, turn)
            }
        }
        return true
    }

    private fun pressed(event: MotionEvent) {
        downX = event.x
        downY = event.y
        isOwningGesture = false
        velocity?.recycle()
        velocity = VelocityTracker.obtain().apply { addMovement(event) }
    }

    /**
     * Past the slop, and sideways: this is a turn, not a tap and not a finger going down the
     * page. Taking it here is what stops the pager taking it, and taking it no earlier is what
     * leaves a tap on a link to the web view. From then on every move is the curl's.
     */
    private fun moved(event: MotionEvent) {
        val travel = event.x - downX
        if (isOwningGesture) {
            onDrag?.invoke(ProseDrag.Changed(travel))
        } else if (abs(travel) > slop && abs(travel) >= abs(event.y - downY)) {
            isOwningGesture = true
            onDrag?.invoke(ProseDrag.Began(travel))
        }
    }

    private fun released(event: MotionEvent, turn: (Boolean) -> Unit) {
        val travel = event.x - downX
        val drag = onDrag
        if (drag != null) {
            // A cancelled drag lets go of the page like a finger that lifted, so the page
            // settles rather than staying lifted.
            if (isOwningGesture) drag(ProseDrag.Ended(travel, releaseVelocity()))
        } else if (event.actionMasked == MotionEvent.ACTION_UP) {
            TurnDrag.direction(travel, threshold, isRightToLeft())?.let(turn)
        }
        isOwningGesture = false
        velocity?.recycle()
        velocity = null
    }

    /** The finger's horizontal speed as it left, in pixels per second. */
    private fun releaseVelocity(): Float {
        val tracker = velocity ?: return 0f
        tracker.computeCurrentVelocity(MILLIS_PER_SECOND)
        return tracker.xVelocity
    }

    @Suppress("FunctionName")
    private companion object {
        const val MILLIS_PER_SECOND = 1000

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
 * Readium's own resolved answer -- publisher metadata, then the publication's language,
 * then the app default -- so the reader never guesses at a rule Readium already owns.
 * Task 9.12: the edge taps, the d-pad/arrow keys and the Fast fade swipe are
 * screen-spatial, and Readium's own pagination is the only place that already knows
 * which way the book reads.
 */
internal fun isRightToLeft(navigator: EpubNavigatorFragment?): Boolean =
    navigator?.settings?.value?.readingProgression == ReadingProgression.RTL

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
     *
     * @param isRightToLeft mirrors the band. This reader has no display-order layer of
     *   its own -- Readium paginates the text -- so the mirror happens here, at the one
     *   place a screen position turns into a logical forward/backward call.
     */
    fun outcome(x: Float, width: Float, tapTurnsPages: Boolean, isRightToLeft: Boolean = false): Boolean? {
        if (!tapTurnsPages) return null
        val band = width * EDGE_FRACTION
        return when {
            x < band -> isRightToLeft
            x > width - band -> !isRightToLeft
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
        /**
         * @param isRightToLeft mirrors only the d-pad arrows, which are spatial -- "the
         *   page to the right" -- the way an edge tap is. Page Up/Down and Space stay
         *   put: they move "the next page to read", regardless of which way the book
         *   reads, the same split the comic reader draws between `turn(target:)` and
         *   `turnInReadingOrder(step:)` in `ReaderScreen.kt`.
         */
        fun of(keyCode: Int, isRightToLeft: Boolean = false): EpubTurnKey? = when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> if (isRightToLeft) TurnForward else TurnBackward
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (isRightToLeft) TurnBackward else TurnForward
            KeyEvent.KEYCODE_PAGE_UP -> TurnBackward
            KeyEvent.KEYCODE_PAGE_DOWN, KeyEvent.KEYCODE_SPACE -> TurnForward
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
