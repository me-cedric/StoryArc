package app.storyarc.core.playback

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
