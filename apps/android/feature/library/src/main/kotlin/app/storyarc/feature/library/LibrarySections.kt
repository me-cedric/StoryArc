package app.storyarc.feature.library

import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import java.util.Locale

/**
 * One heading's worth of shelf.
 *
 * Its own identity rather than the title, because a title can come back: a shelf sorted by
 * title that runs *Saga · Sabrina · Sandman* divides into three sections of which the middle
 * one is a single stray, and two sections headed "S" are two places on the shelf, not one
 * place listed twice.
 */
internal data class LibrarySection(
    val id: String,
    /**
     * What the heading says. A series name, a letter or a year — always data the library
     * already holds, except the one word for everything it cannot place, which the caller
     * supplies translated.
     */
    val title: String,
    val publications: List<Publication>,
)

/**
 * How a long shelf is divided.
 *
 * `library-browsing`: "when the library holds more publications than a reader can scan, then
 * it is divided by series where a publication declares one, and otherwise by the active sort
 * key, with headings that stay visible while their section is on screen — and the sections
 * follow the sort rather than replacing it".
 *
 * That last clause is the whole design. Sections are **contiguous runs of the arranged
 * list**, never a regrouping of it: the shelf stays in exactly the order
 * `LibraryIndex.arrange` put it in, and a heading is opened wherever the key changes. A
 * grouping that gathered every "A" from across a shelf sorted by last-read would silently
 * undo the sort the reader chose, which is the failure this shape exists to avoid.
 *
 * Pure and free of Compose so the rule can be asserted directly — `LibrarySectionsTest` is
 * the reason the awkward cases below are stated once here rather than discovered per
 * screenshot.
 *
 * **This is iOS's `LibrarySections`, case for case**, per the project's rule for logic that
 * exists twice: the same threshold, the same three refusals, the same demotion of a series
 * the sort scatters, and the same tests. The one shape difference is the word for everything
 * the library cannot place: iOS reads it out of its own bundle inside the enum, and a
 * Compose module cannot resolve a string without a composition, so it arrives as a
 * parameter. It is still one word decided in one place — the screen's.
 */
internal object LibrarySections {

    /**
     * Above how many publications a shelf earns structure.
     *
     * "More than a reader can scan" is the requirement's own phrase, and a number is the
     * only way to hold it. A phone shows nine covers at once, so twelve is the first count
     * at which the shelf certainly runs off the bottom with more below — the moment a reader
     * starts scrolling to look for something rather than seeing it. Below it the caller
     * draws one uniform run, which is what the requirement's *when* clause asks for.
     */
    const val THRESHOLD = 12

    /**
     * How many covers a phone shows across, and so the least a heading may cover.
     */
    private const val COVERS_PER_ROW = 3

    /**
     * The shelf, divided — or nothing at all when it divides into nothing.
     *
     * An empty result is a real answer, and the caller draws the plain grid then. Two cases
     * reach it: a sort with no natural divisions (last read, progress, date added, size —
     * all continuous, and a heading over a continuum is an invented boundary), and a shelf
     * whose every publication lands in one section, where a single heading over the whole
     * grid would be a label rather than a structure.
     *
     * @param other what the heading over everything the library cannot place says.
     */
    fun divide(
        publications: List<Publication>,
        sort: LibrarySort,
        other: String,
        locale: Locale = Locale.getDefault(),
    ): List<LibrarySection> {
        if (publications.isEmpty()) return emptyList()

        // A series is only worth a heading when the shelf holds more than one of it. A manga
        // library of three hundred one-shots would otherwise become three hundred headings
        // over one cover each, which is less structure than the wall it replaced, not more.
        val shared = sharedSeries(publications).toMutableSet()
        // And only when the sort keeps it in one place. Sorted by title, *Ashfall #3* is
        // filed under T and *Ashfall #4* under W, with other books between them — two
        // headings reading "Ashfall" are two places on the shelf, and the reader would be
        // right to think the app had lost one of them. So a series the sort scatters is
        // demoted to the sort's own division, which is what "the sections follow the sort
        // rather than replacing it" means when the two disagree.
        shared -= scatteredSeries(publications, sort, shared, other, locale)

        val sections = runs(publications, sort, shared, other, locale)

        // One section is the whole shelf under a heading, which says nothing the shelf did
        // not already say. A key of `null` — a sort that divides into nothing — arrives here
        // the same way, as one run, and leaves by the same door.
        if (sections.size <= 1) return emptyList()
        // No heading twice, for any key and not only for a series. Sorted by series, a
        // library whose standalone titles fall either side of its first series draws *Other*,
        // then that series, then *Other* again — and a reader reasonably reads the second one
        // as a different pile. Where the sort scatters a key that has nowhere left to be
        // demoted to, the division misdescribes the shelf, and no division is the honest
        // answer.
        if (sections.map { it.title }.toSet().size != sections.size) return emptyList()
        // And a heading has to earn its row. A phone shows three covers across, so a
        // division averaging fewer than three per heading costs more vertical space in
        // headings and part-empty rows than the covers it introduces — one dense grid becomes
        // a tall column of announcements. That was not a hypothesis: the test corpus,
        // twenty-two unrelated files with a distinct initial each, drew exactly that on a
        // booted simulator, and it reads worse than the wall it replaced, which is the
        // failure this whole requirement exists to fix, arrived at from the other side.
        if (publications.size < sections.size * COVERS_PER_ROW) return emptyList()
        return sections
    }

    /** The shelf cut wherever the key changes, in the order it arrived. */
    private fun runs(
        publications: List<Publication>,
        sort: LibrarySort,
        sharedSeries: Set<String>,
        other: String,
        locale: Locale,
    ): List<LibrarySection> {
        val sections = mutableListOf<LibrarySection>()
        var currentKey: String? = null
        var current = mutableListOf<Publication>()

        for (publication in publications) {
            val key = key(publication, sort, sharedSeries, other, locale)
            if (key != currentKey) {
                val settled = currentKey
                if (settled != null && current.isNotEmpty()) {
                    sections += section(settled, current, sections.size)
                }
                currentKey = key
                current = mutableListOf()
            }
            current += publication
        }
        val settled = currentKey
        if (settled != null && current.isNotEmpty()) {
            sections += section(settled, current, sections.size)
        }
        return sections
    }

    private fun section(key: String, publications: List<Publication>, index: Int) =
        LibrarySection(id = "$index.$key", title = key, publications = publications.toList())

    /** The series the shelf holds more than one of. */
    private fun sharedSeries(publications: List<Publication>): Set<String> {
        val counts = mutableMapOf<String, Int>()
        for (publication in publications) {
            val series = LibraryIndex.seriesName(publication) ?: continue
            counts[series] = (counts[series] ?: 0) + 1
        }
        return counts.filterValues { it > 1 }.keys
    }

    /** The series this sort does not keep together. */
    private fun scatteredSeries(
        publications: List<Publication>,
        sort: LibrarySort,
        sharedSeries: Set<String>,
        other: String,
        locale: Locale,
    ): Set<String> {
        val seen = mutableSetOf<String>()
        val scattered = mutableSetOf<String>()
        for (section in runs(publications, sort, sharedSeries, other, locale)) {
            if (section.title !in sharedSeries) continue
            if (!seen.add(section.title)) scattered += section.title
        }
        return scattered
    }

    /**
     * Which heading a publication belongs under, or `null` when this sort divides into
     * nothing and the shelf is one run.
     */
    private fun key(
        publication: Publication,
        sort: LibrarySort,
        sharedSeries: Set<String>,
        other: String,
        locale: Locale,
    ): String? {
        // Series first, as the requirement words it. It is checked before the sort's own
        // division rather than after because a reader scanning a shelf recognises *Saga* long
        // before they recognise *S*.
        val series = LibraryIndex.seriesName(publication)
        if (series != null && series in sharedSeries) return series
        return when (sort) {
            // Everything the shelf could not put in a series goes in one place under a sort
            // that is *about* series. Filing them under their initials instead would answer a
            // question the reader did not ask, and would scatter the standalone half of a
            // library across twenty headings that all mean "no series".
            LibrarySort.SERIES -> other

            LibrarySort.TITLE -> initial(publication.displayTitle, other, locale)

            // The year as the file spells it. A publication with none is not "before
            // everything" — the library simply does not know, and `YearRange` treats an
            // unknown year the same way.
            LibrarySort.YEAR -> publication.year?.toString() ?: other

            // Continuous, every one of them. Where the boundary between "recently" and "a
            // while ago" falls is a decision no file carries, and a heading that invented one
            // would be the app asserting something it does not know.
            LibrarySort.LAST_READ,
            LibrarySort.PROGRESS,
            LibrarySort.DATE_ADDED,
            LibrarySort.FILE_SIZE,
            -> null
        }
    }

    /**
     * The letter a title files under, or `#` for everything that files under none.
     *
     * Uppercased for the reader's locale rather than for the machine's: a Turkish shelf files
     * *ısı* under *I*, and an uppercase with no locale would not.
     */
    private fun initial(title: String, other: String, locale: Locale): String {
        val first = title.trim().firstOrNull() ?: return other
        if (!first.isLetter()) return "#"
        return first.toString().uppercase(locale)
    }
}
