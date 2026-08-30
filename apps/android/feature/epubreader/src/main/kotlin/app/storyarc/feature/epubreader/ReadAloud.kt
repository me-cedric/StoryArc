package app.storyarc.feature.epubreader

// What reading aloud is, with no engine in it.
//
// `ebook-reader` asks for speech that starts at the reader's position, follows the page,
// and survives the app going to the background. Almost all of that is platform work —
// an engine, an audio session, a media session — but one part is a decision, and it is
// the part that goes wrong: what a pause *means*.
//
// A reader who pressed pause and a phone call that took the audio away both leave the
// voice silent, and they must not end the same way. When the call ends the book should
// carry on; when the reader pressed pause it must not, or a book starts talking again on
// its own the moment an unrelated notification finishes.
//
// So the cause of the pause is carried with the pause, and the transitions live here
// where they can be asserted without a speaker. iOS pins the same table in `ReadAloud.swift`.

/** Whether the voice is running, stopped, or holding. */
internal enum class ReadAloudState { IDLE, SPEAKING, PAUSED }

/** Who silenced it, which decides whether the end of an interruption starts it again. */
internal enum class PauseCause { READER, INTERRUPTION }

/**
 * The state of reading aloud, and every way it can change.
 *
 * Immutable: each event returns the session that follows it, so a wrong transition is a
 * value a test can compare rather than a field somebody forgot to clear.
 */
internal data class ReadAloudSession(
    val state: ReadAloudState = ReadAloudState.IDLE,
    /** Null unless [state] is [ReadAloudState.PAUSED]. */
    val pausedBy: PauseCause? = null,
) {

    /** Whether a sentence is being spoken right now. */
    val isSpeaking: Boolean get() = state == ReadAloudState.SPEAKING

    /**
     * Whether the transport controls belong on screen at all.
     *
     * Paused counts: a reader who paused still needs the play button, and skipping a
     * sentence while paused is how somebody gets past a sentence they do not want read.
     */
    val isActive: Boolean get() = state != ReadAloudState.IDLE

    /** Starting, or restarting from a new position. */
    fun started(): ReadAloudSession = ReadAloudSession(ReadAloudState.SPEAKING)

    /** The reader pressed pause. Nothing but the reader starts this again. */
    fun pausedByReader(): ReadAloudSession =
        if (isSpeaking) ReadAloudSession(ReadAloudState.PAUSED, PauseCause.READER) else this

    /**
     * Something else took the audio: a call, another app, a spoken direction.
     *
     * A pause the reader already made is left exactly as it was — otherwise a
     * notification arriving during a deliberate pause would convert it into one that
     * resumes on its own.
     */
    fun interrupted(): ReadAloudSession =
        if (isSpeaking) ReadAloudSession(ReadAloudState.PAUSED, PauseCause.INTERRUPTION) else this

    /** The reader pressed play. */
    fun resumed(): ReadAloudSession =
        if (state == ReadAloudState.PAUSED) ReadAloudSession(ReadAloudState.SPEAKING) else this

    /**
     * The interruption is over.
     *
     * [mayResume] is the platform's own answer — iOS puts it in the interruption
     * notification's options, Android in whether the focus came back at all. Speech
     * resumes only when the platform says so *and* the pause was the interruption's.
     */
    fun interruptionEnded(mayResume: Boolean): ReadAloudSession =
        if (mayResume && pausedBy == PauseCause.INTERRUPTION) resumed() else this

    /**
     * The audio is gone for good — another app took it and kept it.
     *
     * Stopped rather than paused: there is nothing to wait for, and a session that sat
     * paused for ever would hold a foreground service open for a book nobody is hearing.
     */
    fun lostAudio(): ReadAloudSession = ReadAloudSession()

    /** The reader closed it, or the book ran out of words. */
    fun stopped(): ReadAloudSession = ReadAloudSession()
}

/**
 * The colour the sentence being spoken is drawn in.
 *
 * Deliberately not one of the five a reader can highlight with, and deliberately not the
 * accent: a mark the reader made is something they can come back to, and the voice's place
 * is not. A neutral at the same weight reads as "the voice is here" without offering itself
 * as a mark — and it stays legible under every reading theme, which a hue would not.
 *
 * iOS draws the same colour from the same three numbers in `ReadAloud.swift`.
 */
internal object SpokenHighlight {
    /** 0.55, 0.55, 0.58 of full, opaque — the iOS values, as the ARGB Android wants. */
    const val TINT: Int = 0xFF8C8C94.toInt()
}

/**
 * What the lock screen says while a book is being read.
 *
 * `ebook-reader` requires the publication title, and a second line is what every media
 * control has room for. The chapter is the better answer — it is what has changed since
 * the reader last looked — and the author is the fallback, because a publication that
 * declares no navigation still has one.
 */
internal data class SpokenLabel(val title: String, val detail: String?) {

    internal companion object {
        fun of(title: String, chapter: String?, author: String?): SpokenLabel =
            SpokenLabel(
                title = title,
                detail = chapter?.trim()?.ifEmpty { null } ?: author?.trim()?.ifEmpty { null },
            )
    }
}
