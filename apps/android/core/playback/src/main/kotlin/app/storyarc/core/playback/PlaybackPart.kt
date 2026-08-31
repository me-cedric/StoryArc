package app.storyarc.core.playback

/**
 * How long a part lasts, when anything knows.
 *
 * The thinnest place in the abstraction, and the design is written around it. A narrated
 * chapter's length comes out of the container and is a fact. A synthesised one is a guess
 * from a character count and a speech rate, and it moves the moment the listener changes
 * the speed — so it is useful for drawing a progress line and must never be *stated* as a
 * total beside a clock.
 *
 * Three cases rather than two, because that difference is real and a two-case type would
 * force the estimate to masquerade as one of the others. [statedMillis] and [isScrubbable]
 * are how the rule is enforced: a surface asks the type, and the type says no.
 */
sealed interface PlaybackDuration {

    /** The container says how long it is. */
    data class Known(val millis: Long) : PlaybackDuration

    /**
     * Nobody says, but it can be guessed — characters divided by a speech rate.
     *
     * `audio-playback` allows a position without a total and forbids inventing one, so
     * this is offered for a progress line and never for a clock.
     */
    data class Estimated(val millis: Long) : PlaybackDuration

    /** Nothing knows, and nothing can guess. */
    data object Unknown : PlaybackDuration

    /**
     * The total a surface may put on screen, or null when there is none to put.
     *
     * Null for [Estimated] on purpose. That is the whole of "reports position without a
     * total rather than inventing one" — the surface has nothing to draw rather than a
     * number it has been told not to trust.
     */
    val statedMillis: Long?
        get() = when (this) {
            is Known -> millis
            is Estimated, Unknown -> null
        }

    /**
     * The best guess at the length, stated or not.
     *
     * For a progress line, which is a proportion and survives being approximate, unlike a
     * clock. Null when nothing knows at all.
     */
    val estimatedMillis: Long?
        get() = when (this) {
            is Known -> millis
            is Estimated -> millis
            Unknown -> null
        }

    /**
     * Whether a scrub control may be offered here.
     *
     * `audio-playback` offers the scrub "where a duration is known": dragging against a
     * guess would move the listener to a place that is not where the handle said.
     */
    val isScrubbable: Boolean get() = this is Known
}

/**
 * One part of a publication being played.
 *
 * A chapter marker, a file in a folder, or a resource in a reading order — the three
 * things the design's table calls a part, and the surfaces never learn which.
 *
 * The title is the **chapter**, not the file. A product decision, recorded as one:
 * `01 - track.mp3` is not what a listener is in the middle of. Where a container offers
 * no name, the part carries whatever the format layer could make of the file name, so the
 * chapter list is never empty.
 */
data class PlaybackPart(
    val title: String,
    val duration: PlaybackDuration = PlaybackDuration.Unknown,
)

/**
 * Where in a publication the audio is.
 *
 * An offset in a named part, which is exactly the shape `reading-progress` asks an
 * audiobook's position to take: "an offset in time within a named part". The part is held
 * by index rather than by title so two parts with the same name stay apart.
 */
data class PlaybackPosition(
    val partIndex: Int,
    val offsetMillis: Long,
)

/**
 * How fast the audio runs.
 *
 * `audio-playback` asks for "at least the range from half speed to triple speed", and the
 * range is the design's product decision: 0.5× to 3×, the range spoken-word listeners
 * actually use. Held as a value rather than a bare `Double` so the clamp happens once,
 * where it can be asserted, instead of at every control that offers it.
 */
@JvmInline
value class PlaybackSpeed private constructor(val rate: Double) {

    /** The number the surface states, with no trailing zero on a whole rate. */
    val label: String
        get() = if (rate == rate.toLong().toDouble()) {
            "${rate.toLong()}×"
        } else {
            "${(Math.round(rate * 100.0) / 100.0)}×"
        }

    companion object {
        const val SLOWEST: Double = 0.5
        const val FASTEST: Double = 3.0

        val NORMAL: PlaybackSpeed = PlaybackSpeed(1.0)

        /** Clamped rather than rejected: a stored rate from a future range still plays. */
        fun of(rate: Double): PlaybackSpeed =
            PlaybackSpeed(rate.coerceIn(SLOWEST, FASTEST))
    }
}
