package app.storyarc.core.model

import kotlin.math.abs
import kotlinx.serialization.Serializable

/**
 * A place in a publication someone marked to come back to.
 *
 * `ebook-reader`: a bookmark "is saved with its chapter title and a text excerpt, and is
 * listed alongside the table of contents". Both of those are stored rather than derived,
 * because deriving them again means opening the resource -- and a list of bookmarks is
 * drawn while the reader is looking at something else.
 *
 * Positioned the way [ReadingPosition.Reflowable] is, and for the reason ADR-0006 gives: a
 * reflowable page number is a function of the reader's own typography and is not stable
 * across devices, so what is written down is a fraction and an opaque locator the renderer
 * understands.
 *
 * iOS's `Bookmark` is the same record.
 */
@Serializable
data class Bookmark(
    val id: String,
    /** What the renderer is handed to go back there. Opaque on purpose. */
    val locator: String,
    /**
     * Which resource it is in, so two marks in different chapters at the same fraction
     * through their own resource are not mistaken for each other.
     */
    val resource: String,
    /** How far through the whole publication, for ordering. */
    val progression: Double,
    /** The chapter it falls in, as the publication's own navigation names it. */
    val chapter: String,
    /** A little of the text there, so the list is readable without opening anything. */
    val excerpt: String,
    val createdAtEpochMillis: Long,
)

/**
 * In book order, not the order they were made.
 *
 * A bookmark list sits beside the table of contents and is read the same way -- as places
 * in the publication. Ordering it by when someone happened to press the button would put
 * chapter nine above chapter two for no reason a reader can see.
 */
fun List<Bookmark>.inReadingOrder(): List<Bookmark> =
    sortedWith(compareBy({ it.progression }, { it.createdAtEpochMillis }))

/**
 * The mark already on this page, if there is one.
 *
 * A reflowable page has no identity of its own -- it is wherever the reader's type size put
 * a break -- so this compares the resource and the fraction through it. Readium reports the
 * *start* of the current page, so two visits to one page give the same number; the tolerance
 * is for the last bit of a `Double`, not for a neighbourhood.
 */
fun List<Bookmark>.markAt(progression: Double, resource: String): Bookmark? =
    firstOrNull { it.resource == resource && abs(it.progression - progression) < 1e-9 }
