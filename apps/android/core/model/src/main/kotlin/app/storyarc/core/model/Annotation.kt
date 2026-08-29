package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * A colour a reader can mark text in.
 *
 * `ebook-reader` asks for "several colours" and does not name them. Five, because a reader
 * who is colour-coding needs enough to mean different things and few enough to remember what
 * each one meant -- and because a row of five fits a selection menu without becoming a
 * palette. Named rather than stored as hex so a theme can render them legibly against its own
 * page colour: yellow on Paper and yellow on Focus are not the same yellow.
 */
enum class HighlightColour { YELLOW, GREEN, BLUE, PINK, PURPLE }

/**
 * Something a reader marked in a publication, with or without a note attached.
 *
 * `ebook-reader`: "highlight in several colours, add a note ... highlights and notes are
 * listed in one place and exportable as plain text or Markdown". One record for both, because
 * a note *is* a highlight with something written on it -- two types would mean two lists, and
 * the spec asks for one.
 *
 * Positioned the way [Bookmark] is and for the same reason (ADR-0006): a fraction through the
 * publication plus the renderer's own locator, which is the only thing that finds the same
 * words again after a type size has moved every page break.
 *
 * iOS's `Annotation` is the same record.
 */
@Serializable
data class Annotation(
    val id: String,
    /** What the renderer is handed to draw it and to go back to it. Opaque on purpose. */
    val locator: String,
    /**
     * Which resource it is in, so two marks at the same fraction of different chapters are
     * not mistaken for each other.
     */
    val resource: String,
    /** How far through the whole publication, for ordering. */
    val progression: Double,
    /** The chapter it falls in, as the publication's own navigation names it. */
    val chapter: String,
    /** The words the reader selected. */
    val text: String,
    val colour: HighlightColour = HighlightColour.YELLOW,
    /** What the reader wrote, if anything. Empty is a highlight; non-empty is a note. */
    val note: String = "",
    val createdAtEpochMillis: Long,
) {
    /** Whether the reader wrote something, as opposed to only marking the words. */
    val hasNote: Boolean get() = note.isNotBlank()
}

/**
 * In book order, not the order they were made.
 *
 * The list is read as places in the publication, the way the bookmark list is.
 */
fun List<Annotation>.inReadingOrder(): List<Annotation> =
    sortedWith(compareBy({ it.progression }, { it.createdAtEpochMillis }))
