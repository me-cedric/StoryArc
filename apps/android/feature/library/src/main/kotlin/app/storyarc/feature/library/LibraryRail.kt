package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
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

    /**
     * Where each publication sits in the lazy list, counting everything the grid puts between
     * the cells.
     *
     * `LazyGridState.animateScrollToItem` takes an **item** index, and the grid prepends an
     * optional full-span continue-reading row, opens a sticky header per section and appends a
     * full-span *more from this library* row. So a letter's target is not the publication's
     * position in the shelf, and iOS's `ScrollViewReader` is the reason only one platform needs
     * this: there, a row is addressed by its id.
     *
     * @param leading how many full-span items the grid draws before the first cell — 1 for the
     *   continue-reading row, 0 when it is absent. The trailing row needs no count: nothing
     *   after the last cell is ever a scroll target.
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
                index++
                for (publication in section.publications) indexes[publication.id] = index++
            }
        }
        return indexes
    }
}

/**
 * The index itself, down the trailing edge of the shelf.
 *
 * `library-browsing`'s *The index without sight* scenario is the reason for every
 * accessibility line here rather than an afterthought about them:
 *
 * - the rail is one traversal group with a name, so a screen reader announces *Alphabetical
 *   index* once instead of announcing twenty-seven unexplained characters,
 * - every entry is a real button with a spoken label naming the letter it moves to, because a
 *   single drawn character is not an instruction,
 * - nothing here is the only statement of anything: the shelf's own section headings say the
 *   same thing in the content, so a reader who never meets the rail loses nothing.
 *
 * iOS's `IndexRail` draws and announces the same thing, from the same three rules.
 */
@Composable
internal fun IndexRail(
    entries: List<RailEntry>,
    onChoose: (RailEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (entries.isEmpty()) return
    val palette = LocalStoryArcPalette.current
    // Read before the modifier rather than inside it: a `semantics` block is not a composable
    // scope, so a `stringResource` call in there does not compile.
    val railName = stringResource(R.string.library_index)
    val spoken = entries.associate { it.label to stringResource(R.string.library_index_jump, it.label) }
    Column(
        modifier = modifier
            .fillMaxHeight()
            .padding(end = StoryArcSpace.xs)
            .background(palette.surfaceOverlay, CircleShape)
            .padding(vertical = StoryArcSpace.sm, horizontal = StoryArcSpace.xs)
            .semantics {
                isTraversalGroup = true
                contentDescription = railName
            },
        verticalArrangement = Arrangement.Center,
    ) {
        entries.forEach { entry ->
            val label = spoken.getValue(entry.label)
            Box(
                // A fixed, small target so a shelf holding every letter still fits one
                // column. The rail is centred rather than stretched, so it clips instead of
                // pushing the covers about.
                modifier = Modifier
                    .size(24.dp)
                    .clickable(onClickLabel = label) { onChoose(entry) }
                    .semantics {
                        role = Role.Button
                        contentDescription = label
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = entry.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = palette.textSecondary,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
