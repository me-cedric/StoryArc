package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsFacet
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlinx.coroutines.launch

/**
 * A page of a catalogue: its sections, its publications, and the groups it declares.
 *
 * All on one screen, because a real feed carries all of them -- Calibre-Web puts "Recently
 * added" beside its sections -- and a screen that showed one and hid the others would make
 * most of every catalogue unreachable. iOS's `CatalogueBrowserView` is the same screen.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CatalogueBrowserScreen(
    browser: CatalogueBrowser,
    queue: DownloadQueue,
    onEnter: (title: String, url: String) -> Unit,
    /** Where a chosen publication goes: its own screen, which is where a format is chosen. */
    onSelect: (OpdsEntry) -> Unit,
    onBack: () -> Unit = {},
) {
    val palette = LocalStoryArcPalette.current
    val state by browser.state.collectAsStateWithLifecycle()
    val feed by browser.feed.collectAsStateWithLifecycle()
    val entries by browser.entries.collectAsStateWithLifecycle()
    val downloads by queue.library.collectAsStateWithLifecycle()
    val onDevice = downloads.finished.map { it.id }.toSet()
    val active = downloads.pending

    // The term as typed, and the result of the last search that was not the server's.
    var term by rememberSaveable { mutableStateOf("") }

    // The download the reader is being asked to spend mobile data on, if one is.
    var meteredAsk by remember { mutableStateOf<MeteredAsk?>(null) }

    // `offline-downloads`' *Overriding once*: on a metered link the reader is asked, with
    // the size, before a byte of their allowance is spent. Off it, the tap is the whole
    // interaction it has always been. One lambda for both call sites below, because two
    // copies of this decision is one copy too many.
    val download: (OpdsEntry) -> Unit = { entry ->
        CatalogueAcquisition.best(entry)?.let { link ->
            if (queue.needsMeteredConfirmation(entry)) {
                meteredAsk = MeteredAsk(entry, link, queue.statedBytes(entry))
            } else {
                queue.enqueue(entry, link)
            }
        }
    }

    MeteredConfirmation(
        ask = meteredAsk,
        onDismiss = { meteredAsk = null },
        onConfirm = { asked ->
            meteredAsk = null
            // The grant is this publication's, not the queue's: everything else behind it
            // goes on waiting for Wi-Fi.
            queue.enqueue(asked.entry, asked.acquisition, overridingMeteredConnection = true)
        },
    )
    var filtered by remember { mutableStateOf<List<OpdsEntry>?>(null) }
    val shown = filtered ?: entries
    // The screen's own scope rather than the browser's: a search the reader left behind by
    // walking out of the page should not outlive the page.
    val scope = rememberCoroutineScope()

    LaunchedEffect(browser) { browser.load() }

    // A `Scaffold`, so the grid starts below the status bar and the page has a name and a
    // way back. Without it the first row sat under the system clock and a tap on it went to
    // the status bar instead of the section.
    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = browser.title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.catalogue_back),
                            tint = palette.accent,
                        )
                    }
                },
                actions = {
                    val facets = feed?.facets.orEmpty()
                    if (facets.isNotEmpty()) {
                        FacetMenu(facets) { facet -> onEnter(facet.title, facet.href) }
                    }
                },
            )
        },
    ) { insets ->
        Column(modifier = Modifier.fillMaxSize().padding(insets)) {
            // `opds-catalog`: "searching within that source queries the server rather than
            // filtering locally", and a catalogue with no search "falls back to filtering
            // the cached catalogue, and says so". Both answers came out of
            // `CatalogueBrowser.search`, which until now nothing on Android called.
            CatalogueSearchField(
                value = term,
                onChange = {
                    term = it
                    if (it.isEmpty()) filtered = null
                },
                onSubmit = {
                    // Asked rather than read again when the answer arrives: resolving an
                    // OpenSearch description document is a request, and the reader can
                    // have typed on since.
                    val asked = term
                    scope.launch {
                        when (val outcome = browser.search(asked)) {
                            // A server-answered search opens as its own page, like entering
                            // a section, so the reader can go back to where they searched
                            // from.
                            is CatalogueBrowser.SearchOutcome.Server -> {
                                filtered = null
                                onEnter(asked, outcome.url)
                            }

                            is CatalogueBrowser.SearchOutcome.Local -> filtered = outcome.matches
                            CatalogueBrowser.SearchOutcome.Cleared -> filtered = null
                        }
                    }
                },
            )
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 140.dp),
                contentPadding = PaddingValues(StoryArcSpace.gutter),
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
                modifier = Modifier.weight(1f),
            ) {
                feed?.navigation?.takeIf { it.isNotEmpty() }?.let { sections ->
                    items(sections, span = { GridItemSpan(maxLineSpan) }) { section ->
                        CatalogueSectionRow(section) { onEnter(section.title, section.href) }
                    }
                }

                if (filtered != null) {
                    // `opds-catalog`: a catalogue with no search "falls back to filtering
                    // the cached catalogue, and says so". This is the saying so.
                    item(span = { GridItemSpan(maxLineSpan) }, key = "local-search") {
                        Text(
                            text = stringResource(R.string.catalogue_search_local),
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.textSecondary,
                        )
                    }
                }

                itemsIndexed(shown, key = { _, entry -> entry.id }) { index, entry ->
                    CatalogueEntryCell(
                        entry = entry,
                        credential = browser.credential,
                        client = browser.client,
                        isDownloaded = entry.id in onDevice,
                        onSelect = { onSelect(entry) },
                        // `offline-downloads`: "the app SHALL let a user download any
                        // publication from a remote source for offline reading". A reader
                        // packing for a flight wants the download without the reading, and
                        // without a walk through the detail screen either.
                        onDownload = { download(entry) },
                        onRemove = { queue.remove(entry.id) },
                    )
                    // The next page arrives because the reader scrolled, not because they
                    // pressed anything. Skipped while a local filter is showing: the filter
                    // is over what is loaded, and loading more would change it underneath.
                    if (filtered == null) {
                        LaunchedEffect(index, shown.size) { browser.loadMore(index) }
                    }
                }

                // After the feed's own publications, because a group is a named part of the
                // page and the page's own run of covers is the unnamed rest of it. Hidden
                // while a local filter is showing: the filter is over a flat list of
                // matches, and a match has left the group it was found in.
                //
                // Keyed by position rather than by title: nothing in the standard makes a
                // group's name unique, and two groups sharing one would collapse into a row.
                feed?.groups?.takeIf { filtered == null }?.let { groups ->
                    itemsIndexed(
                        groups,
                        span = { _, _ -> GridItemSpan(maxLineSpan) },
                    ) { _, group ->
                        CatalogueGroupSection(
                            group = group,
                            credential = browser.credential,
                            client = browser.client,
                            onDevice = onDevice,
                            onEnter = onEnter,
                            onSelect = onSelect,
                            onDownload = download,
                            onRemove = { entry -> queue.remove(entry.id) },
                        )
                    }
                }

                item(span = { GridItemSpan(maxLineSpan) }) {
                    when (val current = state) {
                        is CatalogueBrowser.State.Loading -> Box(
                            modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.xl),
                            contentAlignment = Alignment.Center,
                        ) { CircularProgressIndicator() }

                        is CatalogueBrowser.State.Failed -> Surface(
                            color = palette.surfaceRaised,
                            shape = RoundedCornerShape(StoryArcRadius.md),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(
                                text = current.message,
                                style = MaterialTheme.typography.bodyMedium,
                                color = palette.textPrimary,
                                modifier = Modifier
                                    .clickable { browser.reload() }
                                    .padding(StoryArcSpace.md),
                            )
                        }

                        is CatalogueBrowser.State.Ready ->
                            // The groups count too: a 2.0 feed that puts everything in them
                            // has no top-level anything, and calling that empty told readers
                            // their catalogue was.
                            if (shown.isEmpty() && feed?.isEmpty != false) {
                                Text(
                                    text = stringResource(R.string.catalogue_empty),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = palette.textSecondary,
                                    modifier = Modifier.padding(StoryArcSpace.xl),
                                )
                            }

                        is CatalogueBrowser.State.Idle -> Unit
                    }
                }
            }

            active.firstOrNull()?.let { first ->
                DownloadBanner(
                    download = first,
                    others = active.size - 1,
                    onCancel = { queue.cancel(first.id) },
                    onResume = { queue.resume(first.id) },
                )
            }
        }
    }
}

/**
 * Where a catalogue is asked a question.
 *
 * Submitted rather than debounced, unlike the library's own field. A keystroke there is a
 * pass over what is already in memory; a keystroke here can be a request to somebody's home
 * server, and a server asked once per letter of "sandman" is a server being hammered.
 * iOS's `.searchable` with `onSubmit(of: .search)` is the same decision.
 */
@Composable
private fun CatalogueSearchField(
    value: String,
    onChange: (String) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        singleLine = true,
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        placeholder = { Text(stringResource(R.string.catalogue_search_prompt)) },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    )
}

/**
 * The filters the server offers, grouped as the feed grouped them.
 *
 * A facet is a link to a filtered view of the same feed, so choosing one enters a page like
 * any other section. Grouped because facets in one group are alternatives to each other,
 * which is what makes them a filter rather than a list.
 */
@Composable
private fun FacetMenu(facets: List<OpdsFacet>, onChoose: (OpdsFacet) -> Unit) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.Sort,
            contentDescription = stringResource(R.string.catalogue_facets),
            tint = palette.accent,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        facets.groupBy { it.group }.toSortedMap().forEach { (group, members) ->
            Text(
                text = group,
                style = MaterialTheme.typography.labelSmall,
                color = palette.textSecondary,
                modifier = Modifier.padding(
                    horizontal = StoryArcSpace.md,
                    vertical = StoryArcSpace.xs,
                ),
            )
            members.forEach { facet ->
                DropdownMenuItem(
                    text = { Text(facet.title) },
                    trailingIcon = {
                        if (facet.isActive) {
                            Icon(Icons.Filled.Check, contentDescription = null)
                        }
                    },
                    onClick = {
                        open = false
                        onChoose(facet)
                    },
                )
            }
        }
    }
}
