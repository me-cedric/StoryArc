package app.storyarc.feature.library

import app.storyarc.core.model.Publication

/**
 * The rest of a publication's series, in volume and chapter order.
 *
 * `publication-detail`: "the rest of that series is offered as a shelf, in volume and
 * chapter order". Not a second detail screen and not a series screen — whether a series
 * deserves one of those is a later question the proposal explicitly leaves open.
 *
 * `LibraryIndex.next` answers a neighbouring question for the reader and answers it with
 * the issue number alone, because that is all the end of a chapter needs. A shelf needs
 * the whole run and needs volumes to sort before numbers, so a set of collected editions
 * does not interleave with the issues inside them. The number parsing is deliberately the
 * same shape as `LibraryIndex`'s: "3.5" and "Annual 1" are both real, and a publication
 * with no number sorts last so a one-off stays out of the middle of a numbered run.
 *
 * Empty when the publication names no series, or when the library holds nothing else in
 * it — which the screen draws as an absent shelf rather than an empty one.
 */
internal fun restOfSeries(publication: Publication, library: List<Publication>): List<Publication> {
    val series = publication.series?.trim()?.takeIf { it.isNotEmpty() } ?: return emptyList()
    return library
        .filter { it.id != publication.id && it.series?.trim() == series }
        .distinctBy { it.id }
        .sortedWith(
            compareBy(
                { it.volume ?: Int.MAX_VALUE },
                { issueNumber(it) },
                { it.displayTitle },
            ),
        )
}

/**
 * An issue number as a number, so #10 follows #9.
 *
 * A copy of `LibraryIndex`'s private rule rather than a call to it, because the model
 * keeps it private and a shelf that ordered issues differently from the next-chapter
 * action would be the two disagreeing in front of the reader.
 */
private fun issueNumber(publication: Publication): Double =
    publication.number?.filter { it.isDigit() || it == '.' }?.toDoubleOrNull()
        ?: Double.MAX_VALUE
