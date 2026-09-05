package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.SourceRegistry

/**
 * The controls a reader touches on most visits, under the bar rather than inside it.
 *
 * Four things, in the order they answer questions: **what is available**, then how the
 * shelf is ordered, then what is being hidden, then whether it is covers or rows. The
 * first three are chips because Material's own filter guidance puts a persistent
 * narrowing choice on a chip row rather than behind an icon — a chip says what it is
 * doing in a word, which is exactly what eight identical orange glyphs could not.
 *
 * **The row wraps rather than scrolling sideways, and that is a correction.** It scrolled
 * before, on the argument that a 320 dp window at the largest text size then lost nothing
 * because every control stayed reachable. The emulator disagreed:
 * `docs/designs/screenshots/after-2026-08-31/android-shelf-caption-scale2-light.png` shows
 * *Filter* half out of the window at `font_scale 2.0` with **nothing on screen saying the
 * row scrolls**. Reachable through an interaction a reader has no reason to attempt is not
 * reachable, and `design.md` §3 asks every screen to survive the largest accessibility text
 * size rather than to survive it for whoever guesses right.
 *
 * Wrapping has no affordance to discover: at the largest text size the four controls take
 * two or three lines and all of them are simply on screen. The cost is a taller header
 * exactly where the text is largest, which is the trade Material makes for a chip group
 * too.
 *
 * It does not cover one case — a single chip wider than the line it sits on — and this row
 * reaches that case. The row is padded by [StoryArcSpace.gutter] on both sides inside a
 * window with no further inset of its own, so at 320 dp it is 280 dp across, and the sort
 * chip carries the same `LibrarySort` labels `ListOrderChips` draws: built the same way, at
 * `font_scale 2.0`, that chip wants 357 dp for `Tamaño en este dispositivo`, more than the
 * whole window. Nothing is truncated to buy the wrap, because the chip does not truncate —
 * a label is ordinary text, so it takes a second line inside the chip and the chip grows
 * taller. `ListOrderChipsWrapTest` measures that on the other row; this one has no such
 * test, and the claim that its longest label fits one line was wrong in both directions.
 */
@Composable
internal fun LibraryControls(
    query: LibraryQuery,
    registry: SourceRegistry,
    layout: LibraryLayout,
    availability: LibraryAvailability,
    downloads: DownloadFilter,
    onAvailabilityChange: (LibraryAvailability) -> Unit,
    onQueryChange: (LibraryQuery) -> Unit,
    onDownloadsChange: (DownloadFilter) -> Unit,
    onLayoutChange: (LibraryLayout) -> Unit,
    onClearFilters: () -> Unit,
    viewModel: LibraryViewModel,
    modifier: Modifier = Modifier,
) {
    FlowRow(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        AvailabilityChip(availability, onAvailabilityChange)
        SortChip(query, onQueryChange)
        FilterChipMenu(
            query = query,
            registry = registry,
            downloads = downloads,
            viewModel = viewModel,
            onQueryChange = onQueryChange,
            onDownloadsChange = onDownloadsChange,
            onClearFilters = onClearFilters,
        )
        LayoutToggle(layout, onLayoutChange)
    }
}

/**
 * The library's primary axis, first in the row and never behind a sheet.
 *
 * `library-browsing` asks for it "reachable without opening the filter sheet", and asks
 * that it be "visible while it is active" — a selected chip is both, and it says which of
 * the two states it is in without a legend.
 *
 * One chip rather than a two-button segmented pair: the wide half of this axis is the
 * library's normal state, so it needs no control of its own, and a pair would spend twice
 * the width of a phone's chip row saying so.
 */
@Composable
private fun AvailabilityChip(
    availability: LibraryAvailability,
    onChange: (LibraryAvailability) -> Unit,
) {
    val narrowed = availability.isNarrowing
    FilterChip(
        selected = narrowed,
        onClick = {
            onChange(
                if (narrowed) LibraryAvailability.EVERYTHING else LibraryAvailability.ON_THIS_DEVICE,
            )
        },
        label = { Text(stringResource(R.string.source_on_this_device)) },
        leadingIcon = if (narrowed) {
            { Icon(Icons.Filled.Check, contentDescription = null) }
        } else {
            null
        },
    )
}

/**
 * How the library is ordered, named on the chip rather than hidden behind an arrow glyph —
 * and named *as an ordering*, which is [sortChipLabel]'s whole job.
 */
@Composable
private fun SortChip(query: LibraryQuery, onChange: (LibraryQuery) -> Unit) {
    var open by remember { mutableStateOf(false) }

    // The chip and its menu are one item of the wrapping row, not two. A `DropdownMenu` is a
    // popup and measures as nothing, but it still takes a slot -- and a slot of nothing with
    // the row's spacing either side of it is a gap that can push the next chip onto a line it
    // did not need. Boxed, it also keeps opening under its own chip rather than under
    // whatever the row put in the popup's slot. `ListOrderChips` is boxed for both reasons
    // too, and stopped putting its menu beside its chip when it stopped being a `Row`.
    Box {
        FilterChip(
            // Ordering is always on — there is no unsorted library — so the chip carries the
            // answer rather than a state. It is never drawn as selected for that reason.
            selected = false,
            onClick = { open = true },
            label = { Text(sortChipLabel(query.sort)) },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            // Each row states which one it is, because the dot cannot. A `RadioButton` with
            // a null `onClick` applies no `selectable` modifier and so carries no selected
            // state into the semantics tree — the same hole `LibraryFilterMenu`'s
            // `ChosenItem` had, and here the chip's own label at least names the current
            // sort, so a reader could recover it by leaving the menu.
            LibrarySort.entries.forEach { sort ->
                DropdownMenuItem(
                    modifier = Modifier.semantics {
                        role = Role.RadioButton
                        selected = query.sort == sort
                    },
                    text = { Text(stringResource(sort.labelRes)) },
                    leadingIcon = { RadioButton(selected = query.sort == sort, onClick = null) },
                    onClick = { onChange(query.copy(sort = sort)) },
                )
            }
            HorizontalDivider()
            listOf(
                true to R.string.library_sort_ascending,
                false to R.string.library_sort_descending,
            ).forEach { (ascending, label) ->
                DropdownMenuItem(
                    modifier = Modifier.semantics {
                        role = Role.RadioButton
                        selected = query.ascending == ascending
                    },
                    text = { Text(stringResource(label)) },
                    leadingIcon = {
                        RadioButton(selected = query.ascending == ascending, onClick = null)
                    },
                    onClick = { onChange(query.copy(ascending = ascending)) },
                )
            }
        }
    }
}

/**
 * Grid or list.
 *
 * One button that shows the layout it would switch *to*, rather than a segmented
 * control that spends permanent space on a binary choice.
 */
@Composable
private fun LayoutToggle(layout: LibraryLayout, onChange: (LibraryLayout) -> Unit) {
    val palette = LocalStoryArcPalette.current
    val isGrid = layout == LibraryLayout.GRID
    IconButton(
        onClick = { onChange(if (isGrid) LibraryLayout.LIST else LibraryLayout.GRID) },
    ) {
        Icon(
            imageVector = if (isGrid) Icons.AutoMirrored.Filled.List else Icons.Filled.GridView,
            contentDescription = stringResource(
                if (isGrid) R.string.library_layout_list else R.string.library_layout_grid,
            ),
            tint = palette.accent,
        )
    }
}

/**
 * What a chip carrying the current sort says — the ordering, not just the field.
 *
 * `library-browsing`: "an ordering says that it is an ordering ... a reader seeing the field
 * name alone cannot tell a sort from a filter". The chip drew [labelRes] alone, so on the
 * shelf it read *Title* between *On this device* and *Filter* — three chips of which two
 * were narrowing and the middle one was not, and nothing on any of them said which was
 * which. Photographed before the fix in
 * `docs/designs/screenshots/sort-chip-2026-09-01/before-light-default.png`.
 *
 * **A frame around the existing name rather than seven new sentences.** The seven field
 * names are already translated four ways and are already the words the menu uses, so
 * respelling them as *Sorted by size on this device* would put a second wording of the same
 * fact in the same app — the drift `searchScopeLabel` and `originLabel` both exist to avoid
 * — and would break German and Spanish capitalisation, where those names are nouns that
 * keep their capital. A colon takes the capital in its stride in all four languages.
 *
 * Shared by the shelf's [SortChip] and the shelf-detail row's `ListOrderChips`, because the
 * two draw the same seven names and a reader moving between them should not meet two
 * treatments of one idea. `ListOrderChipsWrapTest` measures the composed label rather than
 * the bare one for the same reason.
 *
 * Not applied to the curated order: *The list's order* is already named as an ordering, and
 * `Sort: The list's order` would claim a sort where the whole point is that there is none.
 */
@Composable
internal fun sortChipLabel(sort: LibrarySort): String =
    stringResource(R.string.library_sort_chip, stringResource(sort.labelRes))

/**
 * How the browsing enums are named on screen.
 *
 * The enums live in `:core:model` and carry no resources: the domain has no
 * business holding UI copy. Naming them is presentation, so it lives here.
 *
 * Still the plain field name, because the menu's own rows need exactly that: inside a menu
 * headed by the chip, every row is already known to be an ordering, and *Sort: Title* on
 * each of seven rows would say it seven more times. [sortChipLabel] frames it for the one
 * place that needs the frame.
 */
internal val LibrarySort.labelRes: Int
    get() = when (this) {
        LibrarySort.TITLE -> R.string.library_sort_title
        LibrarySort.SERIES -> R.string.library_sort_series
        LibrarySort.LAST_READ -> R.string.library_sort_last_read
        LibrarySort.PROGRESS -> R.string.library_sort_progress
        LibrarySort.YEAR -> R.string.library_sort_year
        LibrarySort.DATE_ADDED -> R.string.library_sort_date_added
        LibrarySort.FILE_SIZE -> R.string.library_sort_file_size
    }
