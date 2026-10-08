package app.storyarc.feature.library

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import java.util.Locale

/**
 * One entry of the index down the side of a long shelf: a letter, and the row it moves to.
 *
 * The row is named by its publication's id rather than by a position, because the position a
 * letter has to scroll to is an **item** index and the grid puts a heading and two full-span
 * rows among its cells. [itemIndexes] does that arithmetic; this stays the shelf's own answer.
 * iOS's `RailEntry` carries the identifier too and needs no arithmetic at all — see
 * `LibraryRail.swift`.
 */
internal data class RailEntry(
    /** The single character the entry draws, or `#` for everything no letter claims. */
    val label: String,
    /** The first row filed under that label. */
    val publicationId: String,
)

/**
 * Which letters a shelf can be indexed by, and where each one starts.
 *
 * `library-browsing`: "an index runs down its trailing edge, holding one entry for each letter
 * the shelf actually files a row under, in the shelf's own order". Two sorts file a row under
 * a letter and five do not, and the requirement's *A sort no letter describes* scenario says
 * the index is then **absent** rather than drawn and inert.
 *
 * **Read off the sort key, never off the section headings.** A section title is a series name,
 * a letter, a year or one translated word for the unplaceable, so a rail built from the
 * headings would be a rail of names — a different control. And it is the *sort key* rather
 * than the raw title, for [LibrarySections]' reason: `library-browsing` alphabetises a title
 * with its leading article ignored, so *The Sandman* files under S and a label read off the
 * raw title would say T in the middle of the S run.
 *
 * Pure and free of Compose, as [LibrarySections] and [LibraryRows] are and for the same
 * reason — `LibraryRailTest` states the awkward cases once here rather than discovering them
 * per screenshot. iOS's `LibraryRail` answers the same cases.
 */
internal object LibraryRail {

    /**
     * The letters this shelf offers, in the shelf's own order, or nothing at all.
     *
     * Three refusals, and each of them is a real answer the caller draws nothing for:
     *
     * - a sort that files no row under a letter,
     * - a shelf short enough to take in at a glance — [LibrarySections.THRESHOLD], the
     *   definition this repository already holds, rather than a second number,
     * - a shelf whose every row files under one letter, where the index moves nowhere.
     *
     * @param locale the language whose alphabet the labels are read in. The reader's, from
     *   the one caller that draws a shelf.
     */
    fun of(
        publications: List<Publication>,
        sort: LibrarySort,
        locale: Locale,
    ): List<RailEntry> {
        if (publications.size <= LibrarySections.THRESHOLD) return emptyList()

        val entries = mutableListOf<RailEntry>()
        val seen = mutableSetOf<String>()
        for (publication in publications) {
            val label = label(publication, sort, locale) ?: return emptyList()
            if (!seen.add(label)) continue
            entries += RailEntry(label, publication.id)
        }
        // One letter over the whole shelf is a label rather than an index, and choosing it
        // would move the shelf nowhere. The same shape [LibrarySections.divide] refuses a
        // single section for.
        return if (entries.size > 1) entries else emptyList()
    }

    /**
     * Which letter a row files under, or `null` when this sort files rows under none.
     *
     * The `null` is the whole of the hide-rather-than-disable decision, and it is checked on
     * the first row: a sort that answers `null` answers it for every row, so [of] returns an
     * empty index the moment it sees one.
     */
    private fun label(publication: Publication, sort: LibrarySort, locale: Locale): String? =
        when (sort) {
            // The key the shelf is ordered by, so the labels run in the shelf's own order.
            LibrarySort.TITLE ->
                initial(LibraryIndex.sortKey(publication.displayTitle, locale), locale)
            // A publication naming no series is `#`, and every one of them is one contiguous
            // run at the end of the shelf — `LibraryIndex` puts the whole pile after every
            // series on purpose, so the index never runs a second alphabet through the first.
            LibrarySort.SERIES -> LibraryIndex.seriesName(publication)
                ?.let { initial(LibraryIndex.sortKey(it, locale), locale) }
                ?: "#"
            // None of these files a row under a letter. Four are continuous, for the reason
            // [LibrarySections] gives; a year divides the shelf and is not a letter, and an
            // index of years is a different control from an A-to-Z.
            LibrarySort.LAST_READ,
            LibrarySort.PROGRESS,
            LibrarySort.YEAR,
            LibrarySort.DATE_ADDED,
            LibrarySort.FILE_SIZE,
            -> null
        }

    /**
     * The letter a key files under, or `#` for everything that files under none.
     *
     * Uppercased for the reader's locale rather than for the machine's: a Turkish shelf files
     * *ısı* under *I*, and an uppercase with no locale would not. The same rule
     * [LibrarySections] applies to a heading, so a heading and an index entry cannot disagree
     * about one row.
     */
    private fun initial(key: String, locale: Locale): String {
        val first = key.trim().firstOrNull() ?: return "#"
        if (!first.isLetter()) return "#"
        return first.toString().uppercase(locale)
    }

    /** The height one rail entry draws at. [IndexRail] draws its letters at this height. */
    val ENTRY_HEIGHT: Dp = 24.dp

    /**
     * Which of these entries fit a space of the given height, one per [entryHeight] -- collapsing
     * to an evenly spaced subset when they do not, the way the system's own fast scroller thins
     * out rather than overlapping.
     *
     * 27 entries of 24 dp need 648 dp, which is taller than a phone held in landscape. **Every
     * input already short enough draws every entry it was given.** This only ever removes some,
     * never reorders or invents one. The subset keeps the first and the last entry and spaces the
     * rest evenly between them. **A letter this drops is still reachable:** [IndexRail] is one
     * scrubber, and [RailScrub] reads the finger's position against the whole alphabet rather
     * than against the letters drawn, so every entry has a place under the finger and the
     * bubble names the one it is on. iOS's `LibraryRail.collapsed` is the twin.
     */
    fun collapsed(entries: List<RailEntry>, fit: Dp, entryHeight: Dp = ENTRY_HEIGHT): List<RailEntry> {
        if (entryHeight <= 0.dp || fit <= 0.dp) return entries
        val capacity = maxOf(1, (fit / entryHeight).toInt())
        if (entries.size <= capacity) return entries
        if (capacity == 1) return listOf(entries.first())
        val kept = mutableListOf<RailEntry>()
        var lastIndex = -1
        for (slot in 0 until capacity) {
            val index = slot * (entries.size - 1) / (capacity - 1)
            if (index == lastIndex) continue
            kept += entries[index]
            lastIndex = index
        }
        return kept
    }

    /**
     * Where each publication sits in the lazy list, counting everything the layout puts between
     * the rows.
     *
     * `animateScrollToItem` takes an **item** index, and both layouts open a sticky header per
     * section; the grid also prepends an optional full-span continue-reading row and appends a
     * full-span *more from this library* row. So a letter's target is not the publication's
     * position in the shelf, and iOS's `ScrollViewReader` is the reason only one platform needs
     * this: there, a row is addressed by its id.
     *
     * Both [CoverGrid] and [CoverList] call this, with the sections they actually draw. A list
     * that passed no sections while it drew headings would move the shelf to the wrong place,
     * which is the exact fault this function exists to prevent.
     *
     * @param leading how many full-span items the layout draws before the first row — 1 for the
     *   grid's continue-reading row, 0 when it is absent and 0 for the list, which leads with
     *   nothing. The trailing row needs no count: nothing after the last row is ever a scroll
     *   target.
     */
    fun itemIndexes(
        publications: List<Publication>,
        sections: List<LibrarySection>,
        leading: Int,
    ): Map<String, Int> {
        val indexes = LinkedHashMap<String, Int>()
        var index = leading
        if (sections.isEmpty()) {
            for (publication in publications) indexes[publication.id] = index++
        } else {
            for (section in sections) {
                val heading = index++
                for ((position, publication) in section.publications.withIndex()) {
                    // **A letter that names the first row of a section scrolls to the
                    // section's heading, not to the row.** A pinned heading is drawn over the
                    // top of the viewport, so a row placed at offset zero sits behind it:
                    // measured on an emulator on 2026-09-11, the row spanned 1043 to 1259 and
                    // the heading 1043 to 1106, which is 63 px of a 216 px row hidden,
                    // including the top of its cover. Landing on the heading shows the
                    // heading and then the whole row, which is also what a reader asking for
                    // M is asking to see.
                    //
                    // A letter can still name a row that is not its section's first — under a
                    // series sort, one *Other* section holds titles filed under many letters —
                    // and that row is scrolled to directly, because no heading names it.
                    indexes[publication.id] = if (position == 0) heading else index
                    index++
                }
            }
        }
        return indexes
    }
}
