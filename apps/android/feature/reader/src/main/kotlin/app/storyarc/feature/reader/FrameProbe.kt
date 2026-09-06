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
     * Read on every frame, because an Android panel changes its refresh rate while the app
     * runs: a rate sampled once can be twice or half the rate the next turn is drawn at, and
     * every frame of that turn would then be judged against a rate no longer in force. iOS
     * reads the interval from `CADisplayLink` on every frame for the same reason.
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
 * `Choreographer` is the platform's own frame clock, so what is counted is the display's
 * cadence rather than this code's idea of time, which is the mistake `page-transitions` asks
 * the instrument to avoid: wall-clock seconds are not frames.
 *
 * The view is held for its display, and the interval is read off that display on every frame.
 * A view holds an activity, so a ticker that outlived its composition would hold an activity
 * too: [cancel] is the way out, and the composition must call it. See `CurledPages`.
 */
internal class FrameTicker(private val view: View) : Choreographer.FrameCallback {

    private var run = FrameRun(isEnabled = false)

    /** A page turn started. */
    fun began() {
        if (run.isRecording) return
        run = FrameRun(isEnabled = FrameProbe.isArmed(view.context))
        run.begin()
        if (!run.isRecording) return
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!run.isRecording) return
        run.record(
            at = frameTimeNanos / NANOS_PER_SECOND,
            expecting = FrameProbe.interval(view),
        )
        Choreographer.getInstance().postFrameCallback(this)
    }

    /** The page turn finished, whether it settled or sprang back. */
    fun ended() {
        if (!run.isRecording) return
        cancel()
        FrameProbe.report(run)
    }

    /**
     * The turn was abandoned: stop counting, and report nothing.
     *
     * A run that never reaches [ended] posts itself again on every frame for the life of the
     * process, because [doFrame] is what schedules the next frame. A drag the reader left the
     * screen on does exactly that. Nothing is reported, because a turn whose end nobody saw
     * has no number worth printing.
     */
    fun cancel() {
        if (!run.isRecording) return
        run.end()
        Choreographer.getInstance().removeFrameCallback(this)
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000.0
    }
}
