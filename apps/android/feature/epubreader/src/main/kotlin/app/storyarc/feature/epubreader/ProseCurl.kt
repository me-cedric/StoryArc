package app.storyarc.feature.epubreader

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.provider.Settings
import android.util.Log
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.ui.platform.AndroidUiDispatcher
import app.storyarc.core.model.CurlTurn
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The finger drives the curl over prose. Task 8.12 of `close-the-audited-gaps`, owner answer O1.
//
// `page-transitions` says the curl "SHALL be driven by the finger, not by a timeline", and the
// EPUB curl ran a fixed 340 ms roll after a tap, a key or a released swipe. Now a drag lifts the
// page and the fold follows the finger. The release follows the comic reader's rule,
// [CurlTurn], with its thresholds and its spring, and a drag that catches a settle takes it over
// from where the page is drawn. A tap, a key or a volume press still turns the page: it runs the
// same spring from 0 to a whole turn. iOS's `ProseCurl.swift` is the twin.

/** One phase of a finger on the page, as [TurnInterceptor] reports it, in pixels. */
internal sealed interface ProseDrag {
    data class Began(val travel: Float) : ProseDrag

    data class Changed(val travel: Float) : ProseDrag

    /** @param velocity pixels per second, horizontal. */
    data class Ended(val travel: Float, val velocity: Float) : ProseDrag
}

/**
 * The arithmetic of one prose turn, apart from the views, so it can be asserted.
 *
 * A comic page has both neighbours as rasters before the finger lands, so its drag can swing
 * from a turn forward to a turn back. A page of prose has neither until the navigator moves,
 * and the navigator moves one way. So the first sideways travel picks the direction, and the
 * drag is clamped to it: a finger that comes back past where it started holds the page flat,
 * and a release there springs it back.
 */
internal data class ProseCurl(val isForward: Boolean, val isRightToLeft: Boolean) {

    /** Where the page stands after [travel] pixels from [base], in this turn's direction only. */
    fun progress(base: Float, travel: Float, width: Float): Float = CurlTurn.progress(
        base = base,
        travel = travel,
        width = width,
        isRightToLeft = isRightToLeft,
        canTurnBack = !isForward,
        canTurnForward = isForward,
    )

    /**
     * Where a released page springs to: a whole turn, or flat again.
     *
     * @param velocityDp the finger's horizontal speed in dp per second.
     */
    fun target(reached: Float, velocityDp: Float): Float {
        val flick = CurlTurn.flicks(CurlTurn.forward(velocityDp, isRightToLeft), reached)
        return if (CurlTurn.settles(reached, flick)) whole else 0f
    }

    /** A whole turn in this direction, which is also where a tap or a key springs to. */
    val whole: Float get() = if (isForward) 1f else -1f

    companion object {
        /** The turn a drag starts, or null for a drag with no sideways travel yet. */
        fun starting(travel: Float, isRightToLeft: Boolean): ProseCurl? {
            val forward = CurlTurn.forward(travel, isRightToLeft)
            return if (forward == 0f) null else ProseCurl(forward > 0f, isRightToLeft)
        }
    }
}

/** The sheet over the page while a turn runs. See [CurlSheet]. */
internal interface ProseSheet {
    var progress: Float
    var other: Bitmap?

    /** What a whole turn is measured against, in pixels. */
    val turnWidth: Float

    fun remove()
}

/** The book under the sheet. See [NavigatorProsePage]. */
internal interface ProsePage {
    /** Rasters the page as it is now and raises a sheet showing it, flat and whole. */
    fun raise(isRightToLeft: Boolean): ProseSheet?

    /** Moves one page with no animation, and answers whether the page changed. */
    suspend fun move(forward: Boolean): Boolean

    /** The page now on screen, rastered once it has drawn. */
    suspend fun arrived(): Bitmap?
}

/**
 * The comic reader's spring: `spring()`, as `CurledPages` settles a released page.
 *
 * On [AndroidUiDispatcher.Main], which carries the display's frame clock that an [Animatable]
 * needs and the activity's own scope does not.
 */
internal suspend fun springTo(from: Float, to: Float, onFrame: (Float) -> Unit) =
    withContext(AndroidUiDispatcher.Main) {
        Animatable(from).animateTo(to, spring()) { onFrame(value) }
    }

/**
 * Runs prose turns: the lift when a turn starts, the finger, the spring, and the put-back.
 *
 * One per reader. A turn holds a sheet over the book from its first move until its spring
 * lands, and the navigator has moved under that sheet by then. A turn that springs back moves
 * the navigator back under the sheet before the sheet comes off, so the reader is on the page
 * they started from and the sheet never shows a page that is not there.
 *
 * @param spring runs a settle; a test passes one that does not need a display.
 * @param probe told how long the arriving page took, in milliseconds. See [ProseCurlProbe].
 */
internal class ProseCurlDriver(
    private val scope: CoroutineScope,
    private val density: () -> Float,
    private val spring: suspend (Float, Float, (Float) -> Unit) -> Unit = ::springTo,
    private val probe: (Long) -> Unit = {},
) {
    private var sheet: ProseSheet? = null
    private var turn: ProseCurl? = null
    private var move: Deferred<Boolean>? = null
    private var settling: Job? = null
    private var base = 0f
    private var origin = 0f
    private var reached = 0f
    private var isDragging = false

    /** While the navigator goes back under a sheet that sprang back, nothing takes the page. */
    private var isClosing = false

    /** Whether a sheet is over the page. */
    val isTurning: Boolean get() = sheet != null

    fun drag(phase: ProseDrag, page: ProsePage, isRightToLeft: Boolean) {
        when (phase) {
            is ProseDrag.Began -> {
                if (isClosing) return
                val current = sheet
                if (current != null) {
                    // A settle still running is caught where it is drawn.
                    settling?.cancel()
                    settling = null
                    base = current.progress
                } else {
                    val turn = ProseCurl.starting(phase.travel, isRightToLeft) ?: return
                    if (!lift(turn, page)) return
                    base = 0f
                }
                origin = phase.travel
                reached = base
                isDragging = true
            }
            is ProseDrag.Changed -> {
                if (!isDragging) return
                val turn = turn ?: return
                val sheet = sheet ?: return
                reached = turn.progress(base, phase.travel - origin, sheet.turnWidth)
                sheet.progress = reached
            }
            is ProseDrag.Ended -> {
                if (!isDragging) return
                isDragging = false
                val turn = turn ?: return
                settle(turn.target(reached, phase.velocity / density()), page)
            }
        }
    }

    /**
     * A tap, a key or a volume press: the same spring a released drag runs, from flat to whole.
     *
     * @return false when no sheet could be raised, so the caller turns the page plainly.
     */
    fun request(forward: Boolean, page: ProsePage, isRightToLeft: Boolean): Boolean {
        // A finger on the page or a turn in flight outranks the press, as in the comic reader.
        if (isDragging || sheet != null) return true
        val turn = ProseCurl(forward, isRightToLeft)
        if (!lift(turn, page)) return false
        settle(turn.whole, page)
        return true
    }

    /**
     * Raises the sheet over the page and starts the navigator's move under it. The leaving page
     * is rastered while it is on screen, the sheet goes up flat and whole, and the arriving page
     * is rastered once the move lands.
     */
    private fun lift(turn: ProseCurl, page: ProsePage): Boolean {
        val sheet = page.raise(turn.isRightToLeft) ?: return false
        this.sheet = sheet
        this.turn = turn
        val started = System.nanoTime()
        val move = scope.async {
            val moved = page.move(turn.isForward)
            if (moved) {
                page.arrived()?.let { sheet.other = it }
                probe((System.nanoTime() - started) / NANOS_PER_MILLI)
            }
            moved
        }
        this.move = move
        scope.launch {
            // The first or the last page of the book: nothing to turn to, so the sheet goes at
            // once rather than rolling onto the page it started from.
            if (!move.await() && this@ProseCurlDriver.sheet === sheet) close()
        }
        return true
    }

    /** Springs the page to [target], then leaves the reader on the page the spring chose. */
    private fun settle(target: Float, page: ProsePage) {
        val sheet = sheet ?: return
        val turn = turn ?: return
        settling = scope.launch {
            spring(sheet.progress, target) { sheet.progress = it }
            // The sheet went while it sprang, at the first or the last page, and a later turn
            // may own the driver now. iOS's `ProseCurlDriver.settle` holds the same guard.
            if (this@ProseCurlDriver.sheet !== sheet) return@launch
            isClosing = true
            val moved = move?.await() ?: false
            if (target == 0f && moved) page.move(!turn.isForward)
            close()
        }
    }

    private fun close() {
        sheet?.remove()
        sheet = null
        turn = null
        move = null
        settling = null
        isDragging = false
        isClosing = false
    }

    private companion object {
        const val NANOS_PER_MILLI = 1_000_000L
    }
}

/**
 * How long a prose curl waited for its arriving page, written to logcat while `adb` arms the
 * frame probe: `adb shell settings put global storyarc_frame_probe 1`.
 *
 * Task 4.3b, owner answer O14: measure the stall first. iOS measured it in
 * `ProseCurlOnABookTests`; this is the Android half, for an emulator or a phone. The fold stays
 * flat until the arriving page is rastered, so this number is the stall. A release build never
 * logs it.
 */
internal object ProseCurlProbe {
    /** The setting the comic reader's `FrameProbe` reads too, so one switch arms both. */
    const val ARMING_KEY = "storyarc_frame_probe"

    const val TAG = "StoryArcProseCurl"

    fun report(context: Context, millis: Long) {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        if (Settings.Global.getInt(context.contentResolver, ARMING_KEY, 0) != 1) return
        // A context with no display throws rather than answering null.
        val hertz = runCatching { context.display.refreshRate }.getOrNull() ?: return
        Log.i(TAG, "arrived_ms=$millis frames=${(millis * hertz / 1000f).roundToInt()}")
    }
}
