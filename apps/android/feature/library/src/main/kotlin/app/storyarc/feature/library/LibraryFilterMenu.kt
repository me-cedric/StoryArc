package app.storyarc.feature.library

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.YearRange
import java.util.Locale

/**
 * One group of alternatives the reader can narrow by.
 *
 * `library-browsing` names ten facets; these are the seven the app can answer. The
 * enum exists so the menu can show one group at a time — see [FilterMenu].
 */
private enum class FilterSection { READ_STATE, FORMAT, LANGUAGE, PUBLISHER, GENRE, TAG, DECADE }

/**
 * What the library is narrowed to.
 *
 * `library-browsing`: the groups combine with AND, the active count is visible on
 * the control, and one action clears them all. None of that changed when the groups
 * went from two to seven — what changed is that the menu shows one group at a time.
 * A flat menu listing every publisher, genre and tag a real library holds would run
 * past the bottom of the screen long before the reader reached "Clear filters", and
 * the reader would have to scroll a menu to undo a mistake.
 *
 * Split out of `LibraryScreen` for the same reason it grew: the menu is now longer
 * than the screen's own scaffold. iOS's `FilterMenu` uses nested `Menu`s for the
 * same effect — SwiftUI has submenus and `DropdownMenu` does not.
 */
@Composable
internal fun FilterMenu(query: LibraryQuery, viewModel: LibraryViewModel) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }
    var section by remember { mutableStateOf<FilterSection?>(null) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.FilterList,
            contentDescription = if (query.hasFilters) {
                // A plural, not a format. "1 filters active" is wrong in every
                // language, and the count reaches 1 whenever a reader sets one filter.
                pluralStringResource(
                    R.plurals.library_filter_active,
                    query.activeFilterCount,
                    query.activeFilterCount,
                )
            } else {
                stringResource(R.string.library_filter)
            },
            // Colour is never the only signal: the count is in the description.
            tint = if (query.hasFilters) palette.accent else palette.textSecondary,
        )
    }
    DropdownMenu(
        expanded = open,
        onDismissRequest = {
            open = false
            // Reopening lands on the group list rather than wherever the reader was
            // three taps ago, which they have no reason to remember.
            section = null
        },
    ) {
        when (val chosen = section) {
            null -> SectionList(query, viewModel, onOpen = { section = it }, onClear = {
                viewModel.clearFilters()
                open = false
            })

            else -> {
                BackItem(chosen) { section = null }
                SectionValues(chosen, query, viewModel)
            }
        }
    }
}

/** The groups themselves, each one worth opening only if the library has values for it. */
@Composable
private fun SectionList(
    query: LibraryQuery,
    viewModel: LibraryViewModel,
    onOpen: (FilterSection) -> Unit,
    onClear: () -> Unit,
) {
    FilterSection.entries.forEach { section ->
        // A group with nothing in it is left out entirely: an empty "Genre" list
        // tells the reader nothing and costs a tap to find out.
        if (section.hasValues(viewModel)) {
            SectionItem(
                label = stringResource(section.labelRes),
                isActive = section.isActive(query),
                onClick = { onOpen(section) },
            )
        }
    }
    if (query.hasFilters) {
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_filter_clear)) },
            onClick = onClear,
        )
    }
}

/** The values of one group, as the reader ticks them. */
@Composable
private fun SectionValues(section: FilterSection, query: LibraryQuery, viewModel: LibraryViewModel) {
    when (section) {
        FilterSection.READ_STATE -> ReadState.entries.forEach { state ->
            CheckedItem(stringResource(state.labelRes), state in query.readStates) {
                viewModel.setQuery(query.copy(readStates = toggled(query.readStates, state)))
            }
        }

        FilterSection.FORMAT -> viewModel.availableFormats().forEach { format ->
            CheckedItem(format.displayName, format in query.formats) {
                viewModel.setQuery(query.copy(formats = toggled(query.formats, format)))
            }
        }

        // Languages named in themselves. A reader looking for Deutsch is not helped
        // by "German", which is the rule the language setting already follows.
        FilterSection.LANGUAGE -> viewModel.availableLanguages().forEach { code ->
            CheckedItem(languageName(code), code in query.languages) {
                viewModel.setQuery(query.copy(languages = toggled(query.languages, code)))
            }
        }

        FilterSection.PUBLISHER -> viewModel.availablePublishers().forEach { publisher ->
            CheckedItem(publisher, publisher in query.publishers) {
                viewModel.setQuery(query.copy(publishers = toggled(query.publishers, publisher)))
            }
        }

        FilterSection.GENRE -> viewModel.availableGenres().forEach { genre ->
            CheckedItem(genre, genre in query.genres) {
                viewModel.setQuery(query.copy(genres = toggled(query.genres, genre)))
            }
        }

        FilterSection.TAG -> viewModel.availableTags().forEach { tag ->
            CheckedItem(tag, tag in query.tags) {
                viewModel.setQuery(query.copy(tags = toggled(query.tags, tag)))
            }
        }

        FilterSection.DECADE -> DecadeValues(query, viewModel)
    }
}

/**
 * The year range, offered as the decades the library actually spans.
 *
 * Radio buttons rather than the checkboxes every other group uses, because a range
 * is one answer and not a set of them. "Any year" is how it is turned back off — the
 * same act as unticking the last value in any other group.
 */
@Composable
private fun DecadeValues(query: LibraryQuery, viewModel: LibraryViewModel) {
    ChosenItem(stringResource(R.string.library_filter_decade_any), !query.years.isActive) {
        viewModel.setQuery(query.copy(years = YearRange()))
    }
    viewModel.availableDecades().forEach { start ->
        ChosenItem(
            label = stringResource(R.string.library_filter_decade_label, start),
            // Not `years == YearRange(start, start + 9)`: a range set to something
            // that is not a decade is one this control cannot draw, and showing
            // nothing selected is the honest answer to that.
            chosen = query.years.from == start,
        ) {
            viewModel.setQuery(query.copy(years = YearRange(from = start, to = start + 9)))
        }
    }
}

/** A group, and whether the reader has set any of it. */
@Composable
private fun SectionItem(label: String, isActive: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        // The tick is the only thing that says a collapsed group is narrowing the
        // view. Without it the badge would report three active filters and the menu
        // would look untouched.
        leadingIcon = if (isActive) {
            { Icon(Icons.Filled.Check, contentDescription = null) }
        } else {
            null
        },
        trailingIcon = {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        },
        onClick = onClick,
    )
}

/** The way back to the group list, which also names where the reader is. */
@Composable
private fun BackItem(section: FilterSection, onBack: () -> Unit) {
    DropdownMenuItem(
        text = { Text(stringResource(section.labelRes)) },
        leadingIcon = {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = stringResource(R.string.library_filter_back),
            )
        },
        onClick = onBack,
    )
    HorizontalDivider()
}

@Composable
private fun CheckedItem(label: String, checked: Boolean, onToggle: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { Checkbox(checked = checked, onCheckedChange = null) },
        onClick = onToggle,
    )
}

@Composable
private fun ChosenItem(label: String, chosen: Boolean, onChoose: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { RadioButton(selected = chosen, onClick = null) },
        onClick = onChoose,
    )
}

private fun <T> toggled(current: Set<T>, value: T): Set<T> =
    if (value in current) current - value else current + value

/**
 * A language code as its own speakers write it.
 *
 * The same rule Settings follows, duplicated rather than shared: a feature module
 * never depends on another feature module, and this is four lines.
 */
private fun languageName(code: String): String {
    val locale = Locale.forLanguageTag(code)
    return locale.getDisplayLanguage(locale)
        .ifEmpty { code }
        .replaceFirstChar { it.titlecase(locale) }
}

/**
 * How the filter groups are named on screen.
 *
 * The enums live in `:core:model` and carry no resources: the domain has no
 * business holding UI copy. Naming them is presentation, so it lives here.
 */
private val FilterSection.labelRes: Int
    get() = when (this) {
        FilterSection.READ_STATE -> R.string.library_filter_read_state
        FilterSection.FORMAT -> R.string.library_filter_format
        FilterSection.LANGUAGE -> R.string.library_filter_language
        FilterSection.PUBLISHER -> R.string.library_filter_publisher
        FilterSection.GENRE -> R.string.library_filter_genre
        FilterSection.TAG -> R.string.library_filter_tag
        FilterSection.DECADE -> R.string.library_filter_decade
    }

private fun FilterSection.isActive(query: LibraryQuery): Boolean = when (this) {
    FilterSection.READ_STATE -> query.readStates.isNotEmpty()
    FilterSection.FORMAT -> query.formats.isNotEmpty()
    FilterSection.LANGUAGE -> query.languages.isNotEmpty()
    FilterSection.PUBLISHER -> query.publishers.isNotEmpty()
    FilterSection.GENRE -> query.genres.isNotEmpty()
    FilterSection.TAG -> query.tags.isNotEmpty()
    FilterSection.DECADE -> query.years.isActive
}

private fun FilterSection.hasValues(viewModel: LibraryViewModel): Boolean = when (this) {
    // Always offered: the three read states exist whether or not anything is in them,
    // and "Unread" over an empty result is an answer rather than a dead end.
    FilterSection.READ_STATE -> true
    FilterSection.FORMAT -> viewModel.availableFormats().isNotEmpty()
    FilterSection.LANGUAGE -> viewModel.availableLanguages().isNotEmpty()
    FilterSection.PUBLISHER -> viewModel.availablePublishers().isNotEmpty()
    FilterSection.GENRE -> viewModel.availableGenres().isNotEmpty()
    FilterSection.TAG -> viewModel.availableTags().isNotEmpty()
    FilterSection.DECADE -> viewModel.availableDecades().isNotEmpty()
}

private val ReadState.labelRes: Int
    get() = when (this) {
        ReadState.UNREAD -> R.string.library_read_state_unread
        ReadState.IN_PROGRESS -> R.string.library_read_state_in_progress
        ReadState.FINISHED -> R.string.library_read_state_finished
    }
