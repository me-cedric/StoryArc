package app.storyarc.feature.library

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
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
 * The row scrolls sideways rather than wrapping, so a 320 dp window and the largest text
 * size lose nothing: every control stays reachable, which is the half of the top-bar
 * defect that was not about the title.
 */
@Composable
internal fun LibraryControls(
    query: LibraryQuery,
    registry: SourceRegistry,
    layout: LibraryLayout,
    availability: LibraryAvailability,
    onAvailabilityChange: (LibraryAvailability) -> Unit,
    onQueryChange: (LibraryQuery) -> Unit,
    onLayoutChange: (LibraryLayout) -> Unit,
    onClearFilters: () -> Unit,
    viewModel: LibraryViewModel,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvailabilityChip(availability, onAvailabilityChange)
        SortChip(query, onQueryChange)
        FilterChipMenu(query, registry, viewModel, onQueryChange, onClearFilters)
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
 * How the library is ordered, named on the chip rather than hidden behind an arrow glyph.
 */
@Composable
private fun SortChip(query: LibraryQuery, onChange: (LibraryQuery) -> Unit) {
    var open by remember { mutableStateOf(false) }

    FilterChip(
        // Ordering is always on — there is no unsorted library — so the chip carries the
        // answer rather than a state. It is never drawn as selected for that reason.
        selected = false,
        onClick = { open = true },
        label = { Text(stringResource(query.sort.labelRes)) },
    )
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        LibrarySort.entries.forEach { sort ->
            DropdownMenuItem(
                text = { Text(stringResource(sort.labelRes)) },
                leadingIcon = { RadioButton(selected = query.sort == sort, onClick = null) },
                onClick = { onChange(query.copy(sort = sort)) },
            )
        }
        HorizontalDivider()
        listOf(true to R.string.library_sort_ascending, false to R.string.library_sort_descending)
            .forEach { (ascending, label) ->
                DropdownMenuItem(
                    text = { Text(stringResource(label)) },
                    leadingIcon = {
                        RadioButton(selected = query.ascending == ascending, onClick = null)
                    },
                    onClick = { onChange(query.copy(ascending = ascending)) },
                )
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
 * How the browsing enums are named on screen.
 *
 * The enums live in `:core:model` and carry no resources: the domain has no
 * business holding UI copy. Naming them is presentation, so it lives here.
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
