package app.storyarc.core.playback

/**
 * When to stop, chosen by a listener who is falling asleep.
 *
 * `audio-playback`: "a duration or *end of chapter* may be chosen". Two cases rather than a
 * number, because the second one is not a duration at all — it is a place in the book, and
 * how long it is depends on where the listener is when they choose it.
 */
sealed interface SleepAfter {

    /** A stretch of time from now. */
    data class Duration(val millis: Long) : SleepAfter

    /**
     * The end of the part being played.
     *
     * A **product decision**, recorded as one in `design.md`: a music player has no reason
     * to offer this and a book player does, because it is the option a listener falling
     * asleep actually wants — not to be cut off mid-sentence.
     */
    data object EndOfChapter : SleepAfter
}

/**
 * A sleep timer, counting down.
 *
 * Immutable and engine-free, so the interesting parts — when it elapses, how loud the audio
 * is on the way there, and where the listener will start again — can be asserted without a
 * decoder and without waiting for real minutes to pass.
 *
 * **Both cases are held as a remaining time**, and the difference is only in what moves it:
 * a duration counts itself down, and *end of chapter* is re-read from where the audio has
 * reached. That keeps one number on the player — `audio-playback` asks for "the remaining
 * time" to be shown, and a surface that had to ask which kind of timer it was would be the
 * same branch drawn twice.
 */
data class SleepTimer(
    val after: SleepAfter,
    val remainingMillis: Long,
) {

    /** Whether it is time to stop. */
    val hasElapsed: Boolean get() = remainingMillis <= 0

    /**
     * How loud the audio should be, 0…1.
     *
     * `audio-playback`: "playback fades out rather than cutting off when it elapses". A
     * straight ramp over the last [FADE_MILLIS], because a listener who is nearly asleep
     * should not be woken by silence arriving all at once.
     */
    val gain: Float
        get() = when {
            remainingMillis >= FADE_MILLIS -> 1f
            remainingMillis <= 0 -> 0f
            else -> (remainingMillis.toFloat() / FADE_MILLIS.toFloat()).coerceIn(0f, 1f)
        }

    /**
     * The timer a moment later.
     *
     * @param byMillis how much time has passed.
     * @param playing where the audio has reached, for [SleepAfter.EndOfChapter].
     */
    fun ticked(byMillis: Long, playing: NowPlaying?): SleepTimer = when (after) {
        is SleepAfter.Duration ->
            copy(remainingMillis = (remainingMillis - byMillis).coerceAtLeast(0))
        // Re-read rather than counted down: a listener who skips forward inside the chapter
        // has moved the end nearer, and a timer that kept its own count would stop them in
        // the middle of the next one.
        SleepAfter.EndOfChapter ->
            copy(remainingMillis = leftInPart(playing) ?: remainingMillis)
    }

    companion object {

        /**
         * How long the fade lasts, and how far back the listener starts again.
         *
         * One number for both, and that is the argument for it: the fade is exactly the
         * stretch a listener stopped taking in, so starting again where the fade *began* is
         * starting at the last thing they properly heard. `audio-playback` asks for
         * "a little before" and does not say how little; thirty seconds is a **product
         * decision** with no guideline behind it.
         */
        const val FADE_MILLIS: Long = 30_000

        /**
         * The durations offered, in minutes.
         *
         * A **product decision**. Neither Material nor Apple publishes a set, and these are
         * the ones a listener of a book reaches for — long enough to fall asleep in, short
         * enough that the last one is not a whole evening.
         */
        val OFFERED_MINUTES: List<Int> = listOf(5, 15, 30, 45, 60)

        /**
         * A timer for what the listener chose, or **null** when it cannot be honoured.
         *
         * Null for *end of chapter* where nothing knows how long the part is — a session
         * being read aloud has no true duration, and `audio-playback` requires that every
         * control the player offers "works, or is absent — none is present and refusing".
         * So the surface asks here rather than showing an option that would do nothing.
         */
        fun of(after: SleepAfter, playing: NowPlaying?): SleepTimer? = when (after) {
            is SleepAfter.Duration ->
                after.millis.takeIf { it > 0 }?.let { SleepTimer(after, it) }
            SleepAfter.EndOfChapter ->
                leftInPart(playing)?.let { SleepTimer(after, it) }
        }

        /** How much of the current part is left, when the container says how long it is. */
        private fun leftInPart(playing: NowPlaying?): Long? {
            val total = playing?.statedPartDurationMillis ?: return null
            return (total - playing.offsetMillis).coerceAtLeast(0)
        }
    }
}
