package app.storyarc.feature.reader

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * What one page turn cost, counted in frames rather than in seconds.
 *
 * `page-transitions`, *Frame budget*, asks that a transition "holds the display's refresh
 * rate, and a dropped frame during a turn is treated as a defect". Nothing in this repository
 * had ever counted a frame, so the scenario had no instrument that could fail. This is that
 * instrument, and it deliberately states no rate.
 *
 * **The refresh rate is an input, never a constant here.** `FrameProbe` reads it from the
 * display the turn is drawn on and hands it to [record] as `expecting`. This class therefore
 * says nothing about 60 Hz or 120 Hz, and neither does any test of it. An emulator draws at
 * its host's rate, so the only place a number about a reader's phone can be taken is a
 * reader's phone.
 *
 * **What is counted is what the main thread was handed, not what the reader saw.** The frame
 * clock reports the display's vsync. It does not report whether this app drew anything new for
 * that vsync, or whether the compositor showed it. So a turn whose shader misses its deadline
 * on the GPU, while the main thread stays free enough to answer every callback, is reported
 * with no dropped frame. Read a zero as *the main thread kept up*, and never as *the frame
 * budget was met*.
 *
 * iOS's `FrameRun` holds the same arithmetic, rule for rule.
 */
internal class FrameRun(val isEnabled: Boolean) {

    var isRecording = false
        private set

    /** Frame callbacks this app was handed while the turn ran. */
    var delivered = 0
        private set

    /** Frame callbacks the display had room for over the same span and did not hand over. */
    var dropped = 0
        private set

    /** Seconds from the first frame to the last. Zero until a second frame arrives. */
    var span = 0.0
        private set

    private var first: Double? = null
    private var last: Double? = null

    /**
     * Starts counting.
     *
     * A disabled run stays stopped. A run that is already counting is left alone, because a
     * second drag that catches a settling curl continues one turn rather than starting a
     * second one.
     */
    fun begin() {
        if (!isEnabled || isRecording) return
        isRecording = true
        delivered = 0
        dropped = 0
        span = 0.0
        first = null
        last = null
    }

    /**
     * Takes one delivered frame.
     *
     * [expecting] is how long the display said this frame should take. A gap of two intervals
     * means one frame was not delivered. A gap is rounded to whole frames, so jitter below
     * half a frame is not reported as a drop.
     *
     * Two inputs carry no information and are refused rather than guessed at. An interval of
     * zero or less means the display reported no rate. A timestamp no later than the one
     * before it means the clock did not advance. In both cases the frame is counted and
     * nothing is inferred about drops.
     */
    fun record(at: Double, expecting: Double) {
        if (!isRecording) return
        delivered += 1
        val start = first
        if (start == null) first = at else span = max(0.0, at - start)
        val previous = last
        if (previous != null && expecting > 0.0 && at > previous) {
            val frames = min((at - previous) / expecting, GAP_CEILING).roundToInt()
            dropped += max(0, frames - 1)
        }
        last = at
    }

    /** Stops counting and keeps what was counted. */
    fun end() {
        isRecording = false
    }

    private companion object {
        /**
         * A gap wider than this many frames is not a dropped frame, it is a backgrounded app
         * or a display that reported nonsense. Counting it exactly could overflow `Int`;
         * counting it as this keeps the report finite and obviously wrong.
         */
        const val GAP_CEILING = 1000.0
    }
}
