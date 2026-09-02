package app.storyarc.core.playback

import android.content.Context
import android.content.SharedPreferences

/**
 * How far the listener asked a skip to go, kept where the service can read it.
 *
 * `audio-playback` asks for an interval "the listener can configure", which is the clause
 * that makes this a store rather than two constants.
 *
 * **Here rather than in `:core:persistence`**, for [PlaybackMemory]'s reason exactly:
 * [PlaybackService] sets the decoder's own seek increments and labels the notification's two
 * outer buttons, and a service the system has just started to answer the shade carousel has
 * no scope, no database and no time — while `:core:playback` deliberately does not depend on
 * the library's store at all. A second small preferences file is the cost of that boundary,
 * and it is the same cost the resumption memory already pays.
 *
 * Read synchronously, because both readers are already drawing something when they ask.
 */
class SkipPreferences internal constructor(private val preferences: SharedPreferences) {

    /** What the listener chose, or the defaults on a device that has never been asked. */
    fun intervals(): SkipIntervals {
        val back = preferences.getInt(BACK_SECONDS, 0)
        val forward = preferences.getInt(FORWARD_SECONDS, 0)
        // Zero is the answer for a key that was never written, and it is also the one value
        // a skip may never have — a control that moves nothing. So an unset pair is the
        // default pair rather than a stopped one. `SharedPreferences` offers no sentinel
        // beyond the default it is handed, which is why this is read as a pair.
        if (back <= 0 || forward <= 0) return SkipIntervals.DEFAULT
        return SkipIntervals.of(back, forward)
    }

    /** Remembers a choice. Both directions together: they are one setting to a listener. */
    fun remember(intervals: SkipIntervals) {
        preferences.edit()
            .putInt(BACK_SECONDS, intervals.backSeconds)
            .putInt(FORWARD_SECONDS, intervals.forwardSeconds)
            .apply()
    }

    /** Back to the defaults. */
    fun forget() {
        preferences.edit().clear().apply()
    }

    companion object {
        internal const val FILE = "app.storyarc.playback.skip"
        internal const val BACK_SECONDS = "backSeconds"
        internal const val FORWARD_SECONDS = "forwardSeconds"

        fun open(context: Context): SkipPreferences = SkipPreferences(
            context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE),
        )
    }
}
