package app.storyarc.feature.epubreader

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress

// What reading aloud is that playing an audiobook is not.
//
// The session table used to live here — what a pause *means*, and therefore whether a
// finished phone call starts the book again. It is now `:core:playback`'s `PlaybackSession`,
// because `audio-playback` asks the same question of a narrated file and answers it the same
// way, and two copies of one answer is how the two sources come to disagree. Read-aloud
// reads that table rather than owning one.
//
// What is left here is what only a *voice* has: the sentence being spoken, the position that
// sentence makes, the highlight it is drawn in, and the line the transport says about it.
// iOS keeps the same split.

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
