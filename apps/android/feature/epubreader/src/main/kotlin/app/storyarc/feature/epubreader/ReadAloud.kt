package app.storyarc.feature.epubreader

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress

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

    /**
     * What the end of an interruption means for this session.
     *
     * Three answers, not two, and the missing third is the defect this fixes on iOS: it
     * handled the interruption beginning and ending, and an ending the platform would not
     * resume matched neither branch — so the session sat paused for ever, with no position
     * written and nothing telling the listener. Android has always answered the same event
     * as `AUDIOFOCUS_LOSS`, and now both read it off the same table.
     *
     * [mayResume] is the platform's own answer — iOS reads it from the interruption
     * notification's `shouldResume`, Android from whether the focus came back at all rather
     * than being taken outright.
     */
    fun endingInterruption(mayResume: Boolean): InterruptionOutcome = when {
        // Taken for good, and it ends the session whoever silenced it: a session left
        // paused with nothing able to start it is exactly what the spec forbids. That is
        // not the pause being *undone* — the other clause forbids resuming a pause the
        // reader made, and this never resumes one.
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
 * options bitmask on iOS — and the decision underneath them is the same one. iOS pins these
 * three in `ReadAloud.swift`.
 */
internal enum class InterruptionOutcome {
    /** Nothing to do: the voice was not the interruption's to give back. */
    NOTHING,

    /** The audio came back and the pause was the interruption's, so the voice carries on. */
    RESUME,

    /** The audio is gone for good. The session ends, and its position is written first. */
    LOST,
}

/**
 * A book being read aloud: what to say about it, and the way back to it.
 *
 * Held by [ReadAloudHost] rather than by an activity, because the session outlives every
 * screen and the notification that offers the way back is posted by a service that has none.
 *
 * [location], [title] and [series] are exactly what `EpubReaderActivity.intent` is built
 * from, which is what makes the way back buildable from here without asking an activity
 * that may be gone. iOS's `SpokenBook` carries a publication and a URL instead, because a
 * SwiftUI reader is presented from a value rather than started with an intent — the shapes
 * differ because the two platforms start a reader differently, and nothing else does.
 */
internal data class SpokenBook(
    /** The stable id of the publication being spoken. */
    val id: String,
    /** Where the book lives, as the library recorded it. */
    val location: String,
    val title: String,
    val series: String?,
    val author: String?,
    /** The chapter the voice is in, which is the line both transports have room for. */
    val chapter: String? = null,
) {
    /** What the notification and the lock screen both say. */
    val label: SpokenLabel get() = SpokenLabel.of(title, chapter, author)
}

/**
 * Where the voice got to, in the form the progress store takes.
 *
 * The handoff, as a value. The reader used to be the only thing that wrote a position: it
 * wrote on every navigator move, and the page followed the voice, so the two agreed. A
 * session that outlives its screen has no navigator to move, so the voice writes for itself
 * — and what it writes is the decision worth asserting, which is why it is a value rather
 * than a call into a database.
 *
 * `ebook-reader`: the recorded position "is where the voice got to, not where the reading
 * stopped … whether the session ended with the publication open or continued after it was
 * closed". iOS pins the same shape in `ReadAloud.swift`.
 */
internal data class ReachedPosition(
    /**
     * The sentence being spoken, as Readium's own opaque locator JSON.
     *
     * Not a page number: `ebook-reader` requires the position to survive a type-size
     * change, and a reflowable page number cannot.
     */
    val locator: String,
    /** How far through the whole publication, 0..1. */
    val progression: Double,
) {

    /**
     * Whether there is anything worth writing down.
     *
     * A sentence Readium could not turn into a locator is a sentence nothing can resume
     * from, and writing an empty one over a good position is how an hour is lost.
     */
    val isRecordable: Boolean get() = locator.isNotEmpty()

    /** The record `reading-progress` stores. */
    fun record(identity: PublicationIdentity, atEpochMillis: Long): ReadingProgress =
        ReadingProgress(
            identity = identity,
            position = ReadingPosition.Reflowable(progression = progression, locator = locator),
            // The reader's own rule: a reflowable book is finished at the end of its content
            // rather than at a page number.
            isFinished = progression >= FINISHED,
            updatedAtEpochMillis = atEpochMillis,
        )

    internal companion object {
        /** Close enough to the end of the content to count as the end of the book. */
        const val FINISHED: Double = 0.999
    }
}

/**
 * What opening a publication does to a voice that is already speaking.
 *
 * One session at a time. `ebook-reader`: "the session ends at a sentence boundary and the
 * position it reached is recorded before the new publication opens" — two books cannot be
 * read aloud at once, and switching silently would lose a listener's place.
 *
 * The same question answers what a reader coming *back* to the book being spoken does: it
 * picks the voice up rather than starting another. Both live here as a value so they can be
 * asserted without a speech engine, in the way the pause table already is. iOS pins the
 * same three in `ReadAloud.swift`.
 */
internal enum class SessionHandover {
    /** Nothing is speaking. The reader opens silent, as it always did. */
    NONE,

    /**
     * The book being opened is the book being spoken, so the reader observes the session
     * rather than starting another.
     */
    ADOPT,

    /**
     * A different book. The voice ends at the sentence it reached and that position is
     * written down before the new publication draws a word.
     */
    DISPLACE,
    ;

    internal companion object {
        /** @param whileSpeaking the id of the book being spoken, or null for silence. */
        fun opening(publication: String, whileSpeaking: String?): SessionHandover = when {
            whileSpeaking == null -> NONE
            whileSpeaking == publication -> ADOPT
            else -> DISPLACE
        }
    }
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
