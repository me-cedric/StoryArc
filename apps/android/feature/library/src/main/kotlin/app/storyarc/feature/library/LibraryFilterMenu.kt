package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Checkbox
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.YearRange
import java.util.Locale

/**
 * One group of alternatives the reader can narrow by.
 *
 * `library-browsing` names ten facets; these are the nine the app can answer. The
 * enum exists so the menu can show one group at a time — see [FilterChipMenu].
 *
 * [LIBRARY] leads because it is the newest and the one that changed shape: narrowing to a
 * single library used to be a *scope* — a mode with its own control in the top bar, which
 * silently narrowed the search as well and which a reader could be left in without
 * noticing. It is a filter now, cleared by the same action that clears every other filter
 * and counted in the same badge.
 *
 * [DOWNLOAD] sits with [READ_STATE] because the two are the reader's own relationship with a
 * book rather than anything a file says about itself. It is not the availability chip in the
 * row above wearing a second name — [DownloadFilter] sets out the difference at length.
 */
private enum class FilterSection {
    LIBRARY,
    READ_STATE,
    DOWNLOAD,
    FORMAT,
    LANGUAGE,
    PUBLISHER,
    GENRE,
    TAG,
    DECADE,
}

/**
 * What the library is narrowed to.
 *
 * `library-browsing`: the groups combine with AND, the active count is visible on
 * the control, and one action clears them all. The menu shows one group at a time —
 * a flat menu listing every publisher, genre and tag a real library holds would run
 * past the bottom of the screen long before the reader reached "Clear filters", and
 * the reader would have to scroll a menu to undo a mistake.
 *
 * A chip rather than an icon button. The chip says how many filters are active in a word
 * a reader can read at a glance, which the tinted funnel glyph it replaces could not — and
 * it sits in [LibraryControls] beside the axis and the sort, where the three narrowing
 * decisions belong together.
 */
@Composable
internal fun FilterChipMenu(
    query: LibraryQuery,
    registry: SourceRegistry,
    downloads: DownloadFilter,
    viewModel: LibraryViewModel,
    onQueryChange: (LibraryQuery) -> Unit,
    onDownloadsChange: (DownloadFilter) -> Unit,
    onClearFilters: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    var section by remember { mutableStateOf<FilterSection?>(null) }
    val active = narrowingCount(query, downloads)

    // The chip and its menu are one item of [LibraryControls]'s wrapping row, not two. A
    // `DropdownMenu` is a popup and measures as nothing, but it still takes a slot -- and a
    // slot of nothing with the row's spacing either side of it is a gap that can push the
    // next chip onto a line it did not need.
    Box {
        FilterChip(
            selected = active > 0,
            onClick = { open = true },
            label = {
                Text(
                    text = if (active > 0) {
                        // A plural, not a format. "1 filters active" is wrong in every
                        // language, and the count reaches 1 whenever a reader sets one
                        // filter.
                        pluralStringResource(R.plurals.library_filter_active, active, active)
                    } else {
                        stringResource(R.string.library_filter)
                    },
                )
            },
        )
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
                null -> SectionList(
                    query = query,
                    registry = registry,
                    downloads = downloads,
                    viewModel = viewModel,
                    onOpen = { section = it },
                    onClear = {
                        onClearFilters()
                        open = false
                    },
                )

                else -> {
                    BackItem(chosen) { section = null }
                    SectionValues(
                        chosen,
                        query,
                        registry,
                        downloads,
                        viewModel,
                        onQueryChange,
                        onDownloadsChange,
                    )
                }
            }
        }
    }
}

/**
 * How much of the view the reader has narrowed, the library filter and the download group
 * included.
 *
 * `LibraryQuery.activeFilterCount` counts the seven facets it holds and cannot count the
 * other two, which are fields beside it rather than in it. Counted here so the badge matches
 * what "Clear filters" undoes — a chip reading "2 filters active" that clears three things is
 * a chip nobody trusts twice.
 */
private fun narrowingCount(query: LibraryQuery, downloads: DownloadFilter): Int =
    query.activeFilterCount +
        (if (query.scope == LibraryScope.AllSources) 0 else 1) +
        (if (downloads.isActive) 1 else 0)

/** The groups themselves, each one worth opening only if the library has values for it. */
@Composable
private fun SectionList(
    query: LibraryQuery,
    registry: SourceRegistry,
    downloads: DownloadFilter,
    viewModel: LibraryViewModel,
    onOpen: (FilterSection) -> Unit,
    onClear: () -> Unit,
) {
    FilterSection.entries.forEach { section ->
        // A group with nothing in it is left out entirely: an empty "Genre" list
        // tells the reader nothing and costs a tap to find out.
        if (section.hasValues(registry, viewModel)) {
            SectionItem(
                label = stringResource(section.labelRes),
                isActive = section.isActive(query, downloads),
                onClick = { onOpen(section) },
            )
        }
    }
    if (narrowingCount(query, downloads) > 0) {
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_filter_clear)) },
            onClick = onClear,
        )
    }
}

/** The values of one group, as the reader ticks them. */
@Composable
private fun SectionValues(
    section: FilterSection,
    query: LibraryQuery,
    registry: SourceRegistry,
    downloads: DownloadFilter,
    viewModel: LibraryViewModel,
    onQueryChange: (LibraryQuery) -> Unit,
    onDownloadsChange: (DownloadFilter) -> Unit,
) {
    when (section) {
        FilterSection.LIBRARY -> LibraryValues(query, registry, onQueryChange)

        FilterSection.READ_STATE -> ReadState.entries.forEach { state ->
            CheckedItem(stringResource(state.labelRes), state in query.readStates) {
                onQueryChange(query.copy(readStates = toggled(query.readStates, state)))
            }
        }

        FilterSection.DOWNLOAD -> DownloadValues(downloads, onDownloadsChange)

        FilterSection.FORMAT -> viewModel.availableFormats().forEach { format ->
            CheckedItem(format.displayName, format in query.formats) {
                onQueryChange(query.copy(formats = toggled(query.formats, format)))
            }
        }

        // Languages named in themselves. A reader looking for Deutsch is not helped
        // by "German", which is the rule the language setting already follows.
        FilterSection.LANGUAGE -> viewModel.availableLanguages().forEach { code ->
            CheckedItem(languageName(code), code in query.languages) {
                onQueryChange(query.copy(languages = toggled(query.languages, code)))
            }
        }

        FilterSection.PUBLISHER -> viewModel.availablePublishers().forEach { publisher ->
            CheckedItem(publisher, publisher in query.publishers) {
                onQueryChange(query.copy(publishers = toggled(query.publishers, publisher)))
            }
        }

        FilterSection.GENRE -> viewModel.availableGenres().forEach { genre ->
            CheckedItem(genre, genre in query.genres) {
                onQueryChange(query.copy(genres = toggled(query.genres, genre)))
            }
        }

        FilterSection.TAG -> viewModel.availableTags().forEach { tag ->
            CheckedItem(tag, tag in query.tags) {
                onQueryChange(query.copy(tags = toggled(query.tags, tag)))
            }
        }

        FilterSection.DECADE -> DecadeValues(query, viewModel, onQueryChange)
    }
}

/**
 * The libraries a reader has added, offered by name.
 *
 * Radio buttons rather than checkboxes: a publication comes from one library, so a set of
 * them is a question the shelf cannot answer. "Everywhere" is how the filter is turned back
 * off — the same act as unticking the last value in any other group.
 *
 * The registry's order, because `sources` makes that order meaningful and a list that
 * reshuffled it would undo an arrangement the reader made by hand.
 */
@Composable
private fun LibraryValues(
    query: LibraryQuery,
    registry: SourceRegistry,
    onQueryChange: (LibraryQuery) -> Unit,
) {
    ChosenItem(
        label = stringResource(R.string.library_scope_all),
        chosen = query.scope == LibraryScope.AllSources,
    ) {
        onQueryChange(query.copy(scope = LibraryScope.AllSources))
    }
    registry.sources.forEach { source ->
        val scope = LibraryScope.OneSource(source.id)
        ChosenItem(label = source.displayName, chosen = query.scope == scope) {
            onQueryChange(query.copy(scope = scope))
        }
    }
}

/**
 * Whether the app fetched it, per `library-browsing`'s *Filtering offline*.
 *
 * Radio buttons rather than the checkboxes most groups use, and for the reason the decade
 * group has them: a publication is downloaded or it is not, so ticking both answers is the
 * same as ticking neither. "Downloaded or not" is how the group is turned back off, and it is
 * the group's own name because that is exactly what it shows.
 */
@Composable
private fun DownloadValues(downloads: DownloadFilter, onChange: (DownloadFilter) -> Unit) {
    listOf(
        DownloadFilter.EITHER to R.string.library_filter_download,
        DownloadFilter.DOWNLOADED to R.string.library_filter_download_yes,
        DownloadFilter.NOT_DOWNLOADED to R.string.library_filter_download_no,
    ).forEach { (value, label) ->
        ChosenItem(stringResource(label), downloads == value) { onChange(value) }
    }
}

/**
 * The year range, offered as the decades the library actually spans.
 *
 * Radio buttons rather than the checkboxes most groups use, because a range
 * is one answer and not a set of them. "Any year" is how it is turned back off — the
 * same act as unticking the last value in any other group.
 */
@Composable
private fun DecadeValues(
    query: LibraryQuery,
    viewModel: LibraryViewModel,
    onQueryChange: (LibraryQuery) -> Unit,
) {
    ChosenItem(stringResource(R.string.library_filter_decade_any), !query.years.isActive) {
        onQueryChange(query.copy(years = YearRange()))
    }
    viewModel.availableDecades().forEach { start ->
        ChosenItem(
            label = stringResource(R.string.library_filter_decade_label, start),
            // Not `years == YearRange(start, start + 9)`: a range set to something
            // that is not a decade is one this control cannot draw, and showing
            // nothing selected is the honest answer to that.
            chosen = query.years.from == start,
        ) {
            onQueryChange(query.copy(years = YearRange(from = start, to = start + 9)))
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
        FilterSection.LIBRARY -> R.string.library_filter_library
        FilterSection.READ_STATE -> R.string.library_filter_read_state
        FilterSection.DOWNLOAD -> R.string.library_filter_download
        FilterSection.FORMAT -> R.string.library_filter_format
        FilterSection.LANGUAGE -> R.string.library_filter_language
        FilterSection.PUBLISHER -> R.string.library_filter_publisher
        FilterSection.GENRE -> R.string.library_filter_genre
        FilterSection.TAG -> R.string.library_filter_tag
        FilterSection.DECADE -> R.string.library_filter_decade
    }

private fun FilterSection.isActive(
    query: LibraryQuery,
    downloads: DownloadFilter,
): Boolean = when (this) {
    FilterSection.LIBRARY -> query.scope != LibraryScope.AllSources
    FilterSection.READ_STATE -> query.readStates.isNotEmpty()
    FilterSection.DOWNLOAD -> downloads.isActive
    FilterSection.FORMAT -> query.formats.isNotEmpty()
    FilterSection.LANGUAGE -> query.languages.isNotEmpty()
    FilterSection.PUBLISHER -> query.publishers.isNotEmpty()
    FilterSection.GENRE -> query.genres.isNotEmpty()
    FilterSection.TAG -> query.tags.isNotEmpty()
    FilterSection.DECADE -> query.years.isActive
}

private fun FilterSection.hasValues(
    registry: SourceRegistry,
    viewModel: LibraryViewModel,
): Boolean = when (this) {
    // Only with a second library to narrow to. A group whose whole list is "Everywhere"
    // and the one library there is asks the reader nothing.
    FilterSection.LIBRARY -> registry.sources.size > 1
    // Always offered: the three read states exist whether or not anything is in them,
    // and "Unread" over an empty result is an answer rather than a dead end.
    FilterSection.READ_STATE -> true
    // Always offered too, and for the same reason. A library with nothing downloaded still
    // answers "Not downloaded" usefully — that is the question asked the night before a
    // journey, not during one.
    FilterSection.DOWNLOAD -> true
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
