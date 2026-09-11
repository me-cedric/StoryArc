package app.storyarc.feature.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.Publication
import java.util.Locale

/**
 * How one shelf divides: its headings, and the letters down its side.
 *
 * Beside [rememberShelfRows] rather than inside `Shelf`, and for the same reason that one is
 * its own file: `LibraryScreen.kt` sat one line under the 800-line cap after the list gained
 * its headings, and `AGENTS.md` asks for a file split rather than shorter documentation when
 * a file runs out of room. The two values move together — the rail is "cut from the same list
 * the sections are cut from" — so they leave together.
 *
 * iOS holds the same pair as two computed properties on `LibraryView`, in `LibraryContent`.
 */
internal data class ShelfDivision(
    /** The headings, or empty for a shelf that is drawn as one run. */
    val sections: List<LibrarySection>,
    /** The index down the trailing edge, or empty where the shelf files nothing under a letter. */
    val rail: List<RailEntry>,
)

/**
 * The division of `shelved`, recomputed only when something it depends on changes.
 *
 * **Both layouts, which is the fix rather than a tidy-up.** `library-browsing`'s *Sectioning a
 * long library* says "the library", not "the grid", so the list is bound by it too — and the
 * list was handed no sections at all, so it drew no heading at any length. The layout decides
 * only how many columns a heading has to earn: three in a grid, where a heading costs its own
 * row plus the part-empty row it leaves, and one in a list, where it costs a single row.
 *
 * **Nothing divides while a search is running.** Those results are already grouped by why they
 * matched, and a second set of headings across the first would be two answers to one question.
 * The same goes for the alphabet, for the same reason.
 *
 * Every refusal belongs to [LibrarySections]. This decides only that the question is worth
 * asking, and how wide the layout asking it is.
 *
 * @param locale the language the headings are read in. The reader's, for the reason
 *   [LibraryViewModel.rebuild] gives: a heading is the initial of the sort key, and which
 *   article the sort key drops is a fact about the reader's language, so a heading read in the
 *   device's language would name a letter the shelf did not sort on.
 */
@Composable
internal fun rememberShelfDivision(
    shelved: List<Publication>,
    query: LibraryQuery,
    groups: List<MatchGroup>,
    layout: LibraryLayout,
    locale: Locale,
): ShelfDivision {
    // The one word a section can need that is not already on a file.
    val other = stringResource(R.string.library_section_other)
    val long = groups.isEmpty() && shelved.size > LibrarySections.THRESHOLD
    val sections = remember(shelved, query.sort, long, other, locale, layout) {
        val columns = if (layout == LibraryLayout.GRID) LibrarySections.COVERS_PER_ROW else 1
        if (!long) emptyList()
        else LibrarySections.divide(shelved, query.sort, other, columns, locale)
    }
    val rail = remember(shelved, query.sort, groups.isEmpty(), locale) {
        if (groups.isEmpty()) LibraryRail.of(shelved, query.sort, locale) else emptyList()
    }
    return ShelfDivision(sections, rail)
}
