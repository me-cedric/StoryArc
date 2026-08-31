package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import java.util.Locale

/**
 * How a reading list is arranged on screen, over the order it was made in.
 *
 * `collections-and-reading-lists` makes the order the meaning of a reading list — "an ordered
 * sequence where the order carries meaning" — and `library-browsing` asks for two things on
 * top of that. *Default order in a reading list*: the default is "that curated order,
 * labelled as such — not alphabetical". *Overriding a curated order*: another field "applies
 * it for that session", the app "offers a one-tap return to the curated order", and "the
 * curated order itself is not modified".
 *
 * The last clause is why this is a value beside the list rather than a write into it. The
 * order belongs to whoever made the list — a crossover event in publication order, a
 * recommended path — and a reader who wants to see it by size for an evening has not changed
 * anyone's mind about how it should be read. So nothing here touches `ReadingList.entries`:
 * [ListOrdering.arrange] returns a new sequence of identifiers and the list keeps its own.
 *
 * iOS's `ListOrder` mirrors this, with the same cases asserted in both suites.
 */
data class ListOrder(
    /**
     * The field the reader chose, or null for the order the list is in.
     *
     * Null rather than an eighth case on [LibrarySort]: the curated order is not a way of
     * sorting, it is the absence of one, and putting it in the domain enum would offer it to
     * the library shelf where no such order exists.
     */
    val sort: LibrarySort? = null,
    /**
     * Which way a chosen field runs. Meaningless while [sort] is null, and kept anyway so
     * returning to the curated order and leaving it again does not silently flip.
     */
    val ascending: Boolean = true,
) {
    /** Whether the reader is looking at the order the list carries. */
    val isCurated: Boolean get() = sort == null

    /**
     * Whether the entries may be rearranged from here.
     *
     * Only in the curated order, and this is a correctness rule rather than a nicety: the up
     * and down buttons move an entry by the position it occupies *as drawn*, so a move made
     * while a sort was overriding the list would write that position into the curated order
     * and scramble the thing the reader was promised would not change.
     */
    val allowsReordering: Boolean get() = isCurated

    companion object {
        /** The order the list was made in, which is where every reader starts. */
        val CURATED = ListOrder()
    }
}

/**
 * The order itself, applied.
 *
 * Free of Compose, because it is a decision: which entries end up where, and what happens to
 * the ones the library can no longer answer for. Both are worth asserting directly rather
 * than reading off a screen.
 */
object ListOrdering {

    /**
     * The entries as the reader asked to see them.
     *
     * The curated order is handed straight back — not re-sorted into itself, which would make
     * the default depend on a comparator that has nothing to say about it.
     *
     * A chosen field goes through [LibraryIndex.arrange], the library's own comparator, over a
     * query that carries nothing but the sort. Reusing it is the point: a reading list sorted
     * by title has to collate the way the shelf does, and a second comparator would be a
     * second answer to the same question.
     *
     * An entry the library cannot answer for keeps the tail, in the order the list put it in.
     * `collections-and-reading-lists` says such an entry "remains in the list, marked
     * unavailable, and does not break the ordering" — so it is neither dropped nor sorted on
     * facts nobody has. Last, and in the list's own order among its own kind, is the only
     * arrangement that is decidable from what is known.
     */
    fun arrange(
        entries: List<String>,
        order: ListOrder,
        publications: List<Publication>,
        locale: Locale = Locale.getDefault(),
        progress: (Publication) -> LibraryIndex.Progress = { LibraryIndex.Progress.unread },
    ): List<String> {
        val sort = order.sort ?: return entries

        val known = publications.associateBy { it.id }
        val members = entries.mapNotNull { known[it] }
        val sorted = LibraryIndex.arrange(
            publications = members,
            query = LibraryQuery(sort = sort, ascending = order.ascending),
            locale = locale,
            progress = progress,
        )
        return sorted.map { it.id } + entries.filter { it !in known }
    }

    /**
     * Where each entry sits in the order the list was made in, counting from one.
     *
     * The number beside a row is its place in the *list*, never its place on screen. Under a
     * chosen sort that is the more useful of the two — it says where each entry sits in the
     * path someone laid out — and it is the visible proof that the curated order is still
     * there underneath.
     */
    fun positions(entries: List<String>): Map<String, Int> =
        entries.withIndex().associate { (index, entry) -> entry to index + 1 }
}

/**
 * What a reading list is ordered by, and the way back.
 *
 * A chip row, the way `LibraryControls` puts the shelf's own sort on one: a chip says what it
 * is doing in a word, which is exactly what an unlabelled glyph could not. The first chip is
 * named for the order the list is in, so it labels the curated order as curated without a
 * legend — `library-browsing` asks for that and for nothing more elaborate.
 *
 * The second chip appears only while a sort is overriding the list, and is the one tap back
 * that the same requirement asks for. It is named for where it goes rather than for going
 * there, which is what makes a single tap enough to know what will happen.
 *
 * **The row wraps rather than scrolling sideways, and that is the same correction
 * `LibraryControls` already made.** This row scrolled, on the argument every chip stayed
 * reachable; the shelf's own chip row scrolled on that argument too, and the emulator
 * settled it — `android-shelf-caption-scale2-light.png` caught *Filter* half out of the
 * window at `font_scale 2.0` with nothing on screen saying the row scrolled. Reachable
 * through an interaction a reader has no reason to attempt is not reachable, and
 * `design.md` §3 asks every screen to survive the largest accessibility text size rather
 * than to survive it for whoever guesses right.
 *
 * This row is the worse of the two for it, which is why it did not get to keep the scroll:
 * both its chips are named *the list's order* — `Reihenfolge der Liste` in German — so at an
 * accessibility text size it is two of the longest labels in the module on one line, and the
 * second of them is the way back that the reader is most likely to be looking for.
 *
 * Wrapping has no affordance to discover: the chips take a second line and both are simply
 * on screen. It also settles the focus question a fade would have left open — nothing is
 * scrolled out of view, so there is no off-screen chip for TalkBack or a keyboard to have to
 * bring back.
 */
@Composable
internal fun ListOrderChips(
    order: ListOrder,
    onSortChange: (LibrarySort?) -> Unit,
    onDirectionChange: (Boolean) -> Unit,
    onCurated: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }

    FlowRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = StoryArcSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        // The chip and its menu are one item of the wrapping row, not two. A `DropdownMenu`
        // is a popup and measures as nothing, but it still takes a slot -- and in a `Row`
        // that cost nothing, which is why the menu sat beside the chip here first. In a
        // `FlowRow` a slot of nothing with the row's spacing either side of it is a gap that
        // can push the next chip onto a line it did not need. Boxed, it keeps opening under
        // its own chip, which is the arrangement `SortChip` settled on for both reasons.
        Box {
            FilterChip(
                // Ordering is always on — there is no unordered list — so the chip carries
                // the answer rather than a state. It is never drawn as selected for that
                // reason, which is the rule the shelf's own sort chip follows.
                selected = false,
                onClick = { open = true },
                label = { Text(stringResource(order.labelRes)) },
            )
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                ChosenOrderItem(stringResource(R.string.shelves_list_order), order.isCurated) {
                    onSortChange(null)
                }
                LibrarySort.entries.forEach { sort ->
                    ChosenOrderItem(stringResource(sort.labelRes), order.sort == sort) {
                        onSortChange(sort)
                    }
                }
                // A direction for the curated order would be a control with nothing to
                // reverse.
                if (!order.isCurated) {
                    HorizontalDivider()
                    listOf(
                        true to R.string.library_sort_ascending,
                        false to R.string.library_sort_descending,
                    ).forEach { (value, label) ->
                        ChosenOrderItem(stringResource(label), order.ascending == value) {
                            onDirectionChange(value)
                        }
                    }
                }
            }
        }
        if (!order.isCurated) {
            FilterChip(
                selected = false,
                onClick = onCurated,
                label = { Text(stringResource(R.string.shelves_list_order)) },
                leadingIcon = {
                    Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null)
                },
            )
        }
    }
}

@Composable
private fun ChosenOrderItem(label: String, chosen: Boolean, onChoose: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { RadioButton(selected = chosen, onClick = null) },
        onClick = onChoose,
    )
}

/**
 * What the control is called while the list is in this order.
 *
 * The control naming the current order is what labels the curated one as curated. Here rather
 * than on [ListOrder] for the reason `LibrarySort.labelRes` is in `LibraryControls`: naming a
 * value is presentation, and the value itself carries no resources.
 */
private val ListOrder.labelRes: Int
    get() = sort?.labelRes ?: R.string.shelves_list_order
