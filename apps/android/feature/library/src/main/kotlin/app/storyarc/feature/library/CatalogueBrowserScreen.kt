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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsFacet
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace

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

                itemsIndexed(entries, key = { _, entry -> entry.id }) { index, entry ->
                    CatalogueEntryCell(
                        entry = entry,
                        credential = browser.credential,
                        client = browser.client,
                        isDownloaded = entry.id in onDevice,
                        onSelect = { onSelect(entry) },
                        onDownload = {
                            // `offline-downloads`: "the app SHALL let a user download any
                            // publication from a remote source for offline reading". A reader
                            // packing for a flight wants the download without the reading, and
                            // without a walk through the detail screen either.
                            CatalogueAcquisition.best(entry)?.let { queue.enqueue(entry, it) }
                        },
                        onRemove = { queue.remove(entry.id) },
                    )
                    // The next page arrives because the reader scrolled, not because they
                    // pressed anything.
                    LaunchedEffect(index, entries.size) { browser.loadMore(index) }
                }

                // After the feed's own publications, because a group is a named part of the
                // page and the page's own run of covers is the unnamed rest of it.
                //
                // Keyed by position rather than by title: nothing in the standard makes a
                // group's name unique, and two groups sharing one would collapse into a row.
                feed?.groups?.let { groups ->
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
                            onDownload = { entry ->
                                CatalogueAcquisition.best(entry)?.let { queue.enqueue(entry, it) }
                            },
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
                            if (entries.isEmpty() && feed?.isEmpty != false) {
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
