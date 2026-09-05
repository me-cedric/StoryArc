package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.Publication
import app.storyarc.core.model.seriesLine

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
 * The series and the number, when the title is not already both of them.
 *
 * The comparison is against the **composed** line rather than the bare series name, and
 * that is the whole point of the function. A publication filed as `Harbour Lights #1`
 * inside the series `Harbour Lights` passes a bare comparison — the series and the title
 * genuinely differ — and the caption then prints the title's own words back at the reader
 * one line further down. What a caption has to be distinct from is the line above it, so
 * that is what is compared.
 *
 * A publication whose title *is* its series still falls through to its author, because the
 * composed line for a publication with no number is the bare series, and that comparison
 * catches it. One comparison rather than two, on the string that is really drawn.
 *
 * Case-insensitive, matching `seriesLine(series:number:title:)` on iOS: a title inferred
 * from a filename is often the series and the number joined back together, and a difference
 * of case between the two is not a second fact about the publication. The two platforms
 * answer this identically or the shelf says different things on each.
 *
 * One function for the grid caption and the list caption. Two copies of this rule
 * disagreeing would make the layout toggle change what a publication says it is.
 */
internal fun seriesLine(publication: Publication): String? = seriesLine(
    series = publication.series,
    number = publication.number,
    title = publication.displayTitle,
)

/**
 * The same rule over a catalogue entry, which is not a [Publication] and does not become one
 * until it has been fetched.
 *
 * Most feeds are generated from filenames, so most entries already read `Harbour Lights #1` as
 * their *title* — and the detail screen drew the series under it with nothing comparing the
 * two, saying it twice on every such entry. iOS's `SeriesLine.swift` carries the same overload
 * for the same reason.
 */
internal fun seriesLine(entry: OpdsEntry): String? = seriesLine(
    series = entry.series,
    number = entry.seriesIndex?.let { "${it.toInt()}" },
    title = entry.title,
)

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
