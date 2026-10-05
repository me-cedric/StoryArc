package app.storyarc.core.playback

/**
 * What one press of a skip control moves.
 *
 * `audio-playback`, *Both sources look the same*: "every control the player offers works, or
 * is absent — none is present and refusing". A narrated file moves by [SkipIntervals]'
 * seconds. A synthesised voice has no seconds to move by — it has sentences — so a control
 * labelled *30 seconds* over a voice would be a control stating a distance it cannot travel.
 *
 * Declared as data on the source rather than asked of the engine, which is what keeps the
 * one surface from learning which engine is behind it: the player reads this and draws the
 * label, and nothing in it branches on a kind. iOS states the same two cases on
 * `PlaybackSource.skipUnit`.
 */
enum class SkipUnit {

    /** Seconds, by the fixed interval the control states. */
    SECONDS,

    /** One sentence, which is all a synthesised voice can offer. */
    SENTENCE,
}

/**
 * How far a skip goes, in each direction.
 *
 * **The two numbers are a product decision**, recorded as one in `design.md`. Back is the
 * shorter distance. A listener skips back because they missed a sentence. A listener skips
 * forward because they know the part. media3 defaults to 5 s and 15 s. Both are wrong for
 * spoken word, and no platform guidance covers it.
 *
 * `audio-playback` states the interval is not configurable. Two constants say it once, so
 * the app control and the notification button cannot skip by different amounts.
 */
object SkipIntervals {

    const val BACK_SECONDS: Int = 15

    const val FORWARD_SECONDS: Int = 30

    /** How far a press in this direction moves, in milliseconds. */
    fun millis(direction: SkipDirection): Long = seconds(direction) * 1000L

    /** The number that goes on the control's face, for [direction]. */
    fun seconds(direction: SkipDirection): Int = when (direction) {
        SkipDirection.BACK -> BACK_SECONDS
        SkipDirection.FORWARD -> FORWARD_SECONDS
    }
}
