package app.storyarc.core.playback

// What playing a book is, with no engine in it.
//
// This table used to live in `:feature:epubreader` as `ReadAloudSession`, and everything it
// says is as true of a narrated audiobook as of a synthesised voice: a listener who pressed
// pause and a phone call that took the audio away both leave silence, and they must not end
// the same way. `audio-playback` restates the rule for the player — "a pause the listener
// made is never undone this way" — so keeping two copies of it, one per source, would be
// keeping two answers to a question that has one.
//
// So the table moved here and read-aloud reads it from here. That is what makes "both
// sources look the same" a structural property rather than a promise: there is one session
// type, and the surfaces observe it without ever learning which engine advanced it.
//
// iOS pins the same transitions in `PlaybackSession.swift`.

/** Whether the audio is running, stopped, or holding. */
enum class PlaybackState { IDLE, PLAYING, PAUSED }

/** Who silenced it, which decides whether the end of an interruption starts it again. */
enum class PauseCause { LISTENER, INTERRUPTION }

/**
 * The state of playback, and every way it can change.
 *
 * Immutable: each event returns the session that follows it, so a wrong transition is a
 * value a test can compare rather than a field somebody forgot to clear.
 */
data class PlaybackSession(
    val state: PlaybackState = PlaybackState.IDLE,
    /** Null unless [state] is [PlaybackState.PAUSED]. */
    val pausedBy: PauseCause? = null,
) {

    /** Whether audio is coming out right now. */
    val isPlaying: Boolean get() = state == PlaybackState.PLAYING

    /**
     * Whether the transport belongs on screen at all.
     *
     * Paused counts: a listener who paused still needs the play button, and the compact
     * bar carries a paused book exactly as it carries a playing one — `audio-playback`
     * says "something is playing **or paused**".
     */
    val isActive: Boolean get() = state != PlaybackState.IDLE

    /** Starting, or restarting from a new position. */
    fun started(): PlaybackSession = PlaybackSession(PlaybackState.PLAYING)

    /** The listener pressed pause. Nothing but the listener starts this again. */
    fun pausedByListener(): PlaybackSession =
        if (isPlaying) PlaybackSession(PlaybackState.PAUSED, PauseCause.LISTENER) else this

    /**
     * Something else took the audio: a call, another app, a spoken direction.
     *
     * A pause the listener already made is left exactly as it was — otherwise a
     * notification arriving during a deliberate pause would convert it into one that
     * resumes on its own.
     */
    fun interrupted(): PlaybackSession =
        if (isPlaying) PlaybackSession(PlaybackState.PAUSED, PauseCause.INTERRUPTION) else this

    /** The listener pressed play. */
    fun resumed(): PlaybackSession =
        if (state == PlaybackState.PAUSED) PlaybackSession(PlaybackState.PLAYING) else this

    /**
     * The audio is gone for good — another app took it and kept it.
     *
     * Stopped rather than paused: there is nothing to wait for, and a session that sat
     * paused for ever would hold a foreground service open for a book nobody is hearing.
     */
    fun lostAudio(): PlaybackSession = PlaybackSession()

    /** The listener closed it, or the book ran out of words. */
    fun stopped(): PlaybackSession = PlaybackSession()

    /**
     * What the end of an interruption means for this session.
     *
     * Three answers, not two, and the missing third is a defect this table already fixed
     * once on iOS: it handled the interruption beginning and ending, and an ending the
     * platform would not resume matched neither branch — so the session sat paused for
     * ever, with no position written and nothing telling the listener.
     *
     * [mayResume] is the platform's own answer — iOS reads it from the interruption
     * notification's `shouldResume`, Android from whether the focus came back at all
     * rather than being taken outright.
     */
    fun endingInterruption(mayResume: Boolean): InterruptionOutcome = when {
        // Taken for good, and it ends the session whoever silenced it: a session left
        // paused with nothing able to start it is exactly what the spec forbids. That is
        // not the pause being *undone* — the other clause forbids resuming a pause the
        // listener made, and this never resumes one.
        !mayResume -> if (isActive) InterruptionOutcome.LOST else InterruptionOutcome.NOTHING
        pausedBy == PauseCause.INTERRUPTION -> InterruptionOutcome.RESUME
        else -> InterruptionOutcome.NOTHING
    }
}

/**
 * What the end of an interruption does to a session.
 *
 * A value rather than a branch inside each platform's audio callback, because the two
 * callbacks look nothing alike — a stream of focus changes here, one notification with an
 * options bitmask on iOS — and the decision underneath them is the same one.
 */
enum class InterruptionOutcome {
    /** Nothing to do: the audio was not the interruption's to give back. */
    NOTHING,

    /** The audio came back and the pause was the interruption's, so it carries on. */
    RESUME,

    /** The audio is gone for good. The session ends, and its position is written first. */
    LOST,
}

/**
 * What starting a publication does to one that is already playing.
 *
 * One session at a time. `audio-playback`: "the first stops and its position is recorded
 * before the second begins, because two books speaking at once is never what was meant".
 *
 * The same question answers what a listener coming *back* to the book being played does:
 * it picks the session up rather than starting another. Both live here as a value so they
 * can be asserted without an engine.
 */
enum class SessionHandover {
    /** Nothing is playing. The publication opens silent, as it always did. */
    NONE,

    /**
     * The publication being opened is the one being played, so the screen observes the
     * session rather than starting another.
     */
    ADOPT,

    /**
     * A different publication. The first stops at where it reached and that position is
     * written down before the second plays a sound.
     */
    DISPLACE,
    ;

    companion object {
        /** @param whilePlaying the id of the publication being played, or null for silence. */
        fun opening(publication: String, whilePlaying: String?): SessionHandover = when {
            whilePlaying == null -> NONE
            whilePlaying == publication -> ADOPT
            else -> DISPLACE
        }
    }
}
