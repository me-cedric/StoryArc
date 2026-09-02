package app.storyarc.core.playback

/**
 * How far a skip goes, in each direction.
 *
 * **The defaults are a product decision**, recorded as one in `design.md`: 15 seconds back
 * and 30 forward. Back is the shorter because the reason to skip back is "I missed that
 * sentence" and the reason to skip forward is "I know this part". media3's own defaults —
 * `DEFAULT_SEEK_BACK_INCREMENT_MS = 5000` and `DEFAULT_SEEK_FORWARD_INCREMENT_MS = 15000` —
 * are wrong for spoken word in the same direction, and no platform guidance covers it.
 *
 * `audio-playback` requires the interval to be one "the listener can configure", which is
 * why this is a stored value rather than two constants. It mirrors iOS's `SkipIntervals`
 * field for field.
 *
 * A value that clamps rather than an enum of stops: a pair read back out of a preferences
 * file, or arriving from a control, has to land somewhere playable without every caller
 * remembering to check. Same rule as [PlaybackSpeed].
 */
class SkipIntervals private constructor(
    val backSeconds: Int,
    val forwardSeconds: Int,
) {

    // Written out rather than taken from a `data class`, whose generated `copy` would be a
    // public way round the clamp above.
    override fun equals(other: Any?): Boolean = other is SkipIntervals &&
        other.backSeconds == backSeconds && other.forwardSeconds == forwardSeconds

    override fun hashCode(): Int = backSeconds * 31 + forwardSeconds

    override fun toString(): String = "SkipIntervals(back=${backSeconds}s, forward=${forwardSeconds}s)"

    /** How far a press in this direction moves, in milliseconds. */
    fun millis(direction: SkipDirection): Long = when (direction) {
        SkipDirection.BACK -> backSeconds * 1000L
        SkipDirection.FORWARD -> forwardSeconds * 1000L
    }

    /** The number that goes on the control's face, for [direction]. */
    fun seconds(direction: SkipDirection): Int = when (direction) {
        SkipDirection.BACK -> backSeconds
        SkipDirection.FORWARD -> forwardSeconds
    }

    companion object {

        /**
         * The intervals a listener may choose, in seconds.
         *
         * **Not a fifth product decision — the platform's own set.** media3's `CommandButton`
         * ships a numbered glyph for exactly these four in each direction
         * (`ICON_SKIP_BACK_5`, `_10`, `_15`, `_30`, and their forward twins), read off
         * `media3-session-1.11.0.aar`'s constants on 2026-09-02. An interval outside the set
         * leaves the notification with either a lying number or a bare arrow, so offering the
         * four the platform can draw keeps the shade's control and the app's control saying
         * the same thing. Both defaults are in it.
         */
        val OFFERED_SECONDS: List<Int> = listOf(5, 10, 15, 30)

        /** The shortest and longest a stored value may be, which is the offered set's span. */
        private val PERMITTED = OFFERED_SECONDS.first()..OFFERED_SECONDS.last()

        val DEFAULT: SkipIntervals = SkipIntervals(backSeconds = 15, forwardSeconds = 30)

        /** Clamped rather than rejected: a pair stored by another build still plays. */
        fun of(backSeconds: Int, forwardSeconds: Int): SkipIntervals = SkipIntervals(
            backSeconds = backSeconds.coerceIn(PERMITTED),
            forwardSeconds = forwardSeconds.coerceIn(PERMITTED),
        )
    }
}
