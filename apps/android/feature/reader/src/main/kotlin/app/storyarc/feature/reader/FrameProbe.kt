package app.storyarc.feature.reader

import android.content.Context
import android.content.pm.ApplicationInfo
import android.provider.Settings
import android.util.Log
import android.view.Choreographer
import android.view.View
import kotlin.math.roundToInt

/**
 * The switch that arms [FrameRun], and where the report goes.
 *
 * **It is off twice over.** A build that is not debuggable can never arm it, whatever the
 * device is set to, so a release build costs one flag test per turn and nothing else. A
 * debuggable build is armed only while a global setting says so, and only `adb` can write
 * that setting:
 *
 * ```
 * adb shell settings put global storyarc_frame_probe 1
 * ```
 *
 * `scripts/measure-turn.mjs` sets it, reads the reports and puts the setting back.
 *
 * **iOS's `FrameProbe` is the twin, and differs in three ways the platform forces.** It reads
 * its switch once, because a launch argument cannot change while the process lives, while the
 * setting here can be thrown over the cable and the reader does not have to be restarted. It
 * reports to standard output rather than to `logcat`, because that is what `devicectl` reads.
 * And its ticker is reached statically rather than held by the composition, because
 * `CADisplayLink` needs neither a `Context` nor a `View` to find the switch or the rate.
 */
internal object FrameProbe {

    /** The global setting that arms the instrument. */
    const val ARMING_KEY = "storyarc_frame_probe"

    /** The logcat tag the report is written under. */
    const val TAG = "StoryArcFrames"

    fun isArmed(context: Context): Boolean {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return false
        return Settings.Global.getInt(context.contentResolver, ARMING_KEY, 0) == 1
    }

    /**
     * Seconds one frame has on the display this view is drawn on.
     *
     * `Display.getRefreshRate` is the panel's own answer, so a 120 Hz panel reports its
     * interval and a 60 Hz panel reports its own. A view with no display yet reports nothing,
     * and [FrameRun] infers no drops from a zero interval rather than guessing a rate.
     *
     * Read once, because `Choreographer` reports no interval of its own. iOS takes the
     * interval from `CADisplayLink` on every frame instead.
     */
    fun interval(view: View): Double {
        val rate = view.display?.refreshRate?.toDouble() ?: 0.0
        return if (rate > 0.0) 1.0 / rate else 0.0
    }

    /**
     * One line in `logcat`, which `scripts/measure-turn.mjs` reads through `adb`. The same
     * wording as iOS's, so one regular expression reads both.
     */
    fun report(run: FrameRun) {
        Log.i(
            TAG,
            "delivered=${run.delivered} dropped=${run.dropped}" +
                " span_ms=${(run.span * MILLIS_PER_SECOND).roundToInt()}",
        )
    }

    private const val MILLIS_PER_SECOND = 1000.0
}

/**
 * One `Choreographer` callback and the run it feeds.
 *
 * `Choreographer` is the platform's own frame clock, so the count is the display's count. A
 * timer would measure this code's idea of time instead, which is the mistake `page-transitions`
 * asks the instrument to avoid: wall-clock seconds are not frames.
 */
internal class FrameTicker(context: Context, private val interval: Double) :
    Choreographer.FrameCallback {

    /** The application context: this ticker outlives nothing, but it must not hold an activity. */
    private val context = context.applicationContext

    private var run = FrameRun(isEnabled = false)

    /** A page turn started. */
    fun began() {
        if (run.isRecording) return
        run = FrameRun(isEnabled = FrameProbe.isArmed(context))
        run.begin()
        if (!run.isRecording) return
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!run.isRecording) return
        run.record(at = frameTimeNanos / NANOS_PER_SECOND, expecting = interval)
        Choreographer.getInstance().postFrameCallback(this)
    }

    /** The page turn finished, whether it settled or sprang back. */
    fun ended() {
        if (!run.isRecording) return
        run.end()
        Choreographer.getInstance().removeFrameCallback(this)
        FrameProbe.report(run)
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000.0
    }
}
