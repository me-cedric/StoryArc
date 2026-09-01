package app.storyarc.core.playback

/**
 * Something that can be played, with no surface in it.
 *
 * Two implementations: a narrated audiobook decoded by media3, and the read-aloud voice
 * spoken by the device's own engine. The interface is deliberately small and deliberately
 * synchronous — every method below is something a listener asked for, and reporting the
 * result is [onChange]'s job rather than a return value's.
 *
 * **Nothing on this interface names the engine**, which is what makes
 * `audio-playback`'s "both sources look the same" structural: [PlaybackCentre] builds
 * [NowPlaying] out of exactly these members, so a surface built from a `NowPlaying` has
 * nothing to state even if it wanted to.
 */
interface PlayerSource {

    /** The stable id of the publication being played. See `PublicationIdentity`. */
    val publicationId: String

    /** What the publication is called. */
    val title: String

    /**
     * The parts, in playing order.
     *
     * Never empty for a source that can play at all: a publication with no chapter
     * markers has one part standing in for the whole, which is what keeps the chapter
     * list from being empty.
     */
    val parts: List<PlaybackPart>

    /** Where the audio is now. */
    val position: PlaybackPosition

    /** Whether it is playing, paused or idle, and what silenced it. */
    val session: PlaybackSession

    /** How fast it is running. */
    val speed: PlaybackSpeed

    /**
     * How many parts could not be decoded.
     *
     * `publication-formats`: a damaged audiobook "plays what it can and states how much
     * it could not … in the player's own controls rather than interrupting playback". So
     * it is a number the surface reads, never an error that stops anything.
     */
    val skippedPartCount: Int get() = 0

    /** Reports every change to whoever is driving. Set by [PlaybackCentre]. */
    var onChange: (() -> Unit)?

    /**
     * Reports that the thing which took the audio has finished with it.
     *
     * Set by [PlaybackCentre], and separate from [onChange] because the answer is not a
     * redraw: `audio-playback` wants the audio back only when the pause was the
     * interruption's, and the session ended outright when the audio is gone for good.
     * [PlaybackSession.endingInterruption] decides between those three, and the centre is
     * where it is asked — a source that decided for itself would be a second copy of the
     * rule, which is what moving the table into this module removed.
     *
     * Required rather than defaulted: a source that quietly ignored this would be a book
     * that never comes back after a phone call, and nothing in a build would say so.
     *
     * @param mayResume the platform's own answer to whether playback may start again.
     */
    var onInterruptionEnd: ((mayResume: Boolean) -> Unit)?

    fun play()
    fun pause()
    fun stop()
    fun seek(to: PlaybackPosition)
    fun setSpeed(speed: PlaybackSpeed)
}

/**
 * Everything a playback surface draws, and nothing else.
 *
 * The compact bar, the full player, the notification and the lock screen all read this one
 * value. It is built from a [PlayerSource] and carries no reference back to it, so the
 * question "which engine is behind this" is not merely discouraged at a call site — it is
 * unanswerable from what the call site has.
 */
data class NowPlaying(
    val publicationId: String,
    val title: String,
    val parts: List<PlaybackPart>,
    val partIndex: Int,
    val offsetMillis: Long,
    val session: PlaybackSession,
    val speed: PlaybackSpeed,
    val skippedPartCount: Int = 0,
) {

    /** Whether audio is coming out right now. */
    val isPlaying: Boolean get() = session.isPlaying

    /** Whether the compact bar belongs on screen. Paused counts. */
    val isActive: Boolean get() = session.isActive

    /**
     * The name of the part being played.
     *
     * What the compact bar states beside the title, because it is what a listener is in
     * the middle of. Null only for a source with no parts at all, which nothing produces.
     */
    val chapter: String? get() = parts.getOrNull(partIndex)?.title

    /** How long the current part lasts, when anything knows. */
    val partDuration: PlaybackDuration
        get() = parts.getOrNull(partIndex)?.duration ?: PlaybackDuration.Unknown

    /** The current part's total, when there is one a surface may state. */
    val statedPartDurationMillis: Long? get() = partDuration.statedMillis

    /** Whether the scrub control may be offered. */
    val isScrubbable: Boolean get() = partDuration.isScrubbable

    /**
     * The whole publication's length, when **every** part states one.
     *
     * All or nothing on purpose: a total that quietly omits the parts nobody measured is
     * a total a progress line runs past the end of, and half a number is worse than none.
     */
    val statedTotalMillis: Long?
        get() = parts.fold(0L as Long?) { total, part ->
            val stated = part.duration.statedMillis
            if (total == null || stated == null) null else total + stated
        }

    /** How far into the whole publication the audio is, on the same all-or-nothing rule. */
    val elapsedTotalMillis: Long?
        get() {
            if (statedTotalMillis == null) return null
            val before = parts.take(partIndex).sumOf { it.duration.statedMillis ?: 0L }
            return before + offsetMillis
        }

    /** Whether some parts are missing from what the listener will hear. */
    val isPartial: Boolean get() = skippedPartCount > 0

    companion object {
        /** The surface a source produces right now. */
        fun of(source: PlayerSource): NowPlaying = NowPlaying(
            publicationId = source.publicationId,
            title = source.title,
            parts = source.parts,
            partIndex = source.position.partIndex,
            offsetMillis = source.position.offsetMillis,
            session = source.session,
            speed = source.speed,
            skippedPartCount = source.skippedPartCount,
        )
    }
}
