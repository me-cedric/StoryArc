package app.storyarc.feature.library

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsFacet
import app.storyarc.core.catalogue.OpdsSection
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.model.Publication
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.PublicationFormat
import kotlinx.coroutines.launch

/**
 * A page of a catalogue: its sections, then its publications.
 *
 * Both on one screen, because a real feed carries both -- Calibre-Web puts "Recently added"
 * beside its sections -- and a screen that showed one and hid the other would make half of
 * every catalogue unreachable. iOS's `CatalogueBrowserView` is the same screen.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CatalogueBrowserScreen(
    browser: CatalogueBrowser,
    queue: DownloadQueue,
    onEnter: (title: String, url: String) -> Unit,
    onOpen: (Publication, String) -> Unit,
    onBack: () -> Unit = {},
) {
    val palette = LocalStoryArcPalette.current
    val state by browser.state.collectAsStateWithLifecycle()
    val feed by browser.feed.collectAsStateWithLifecycle()
    val entries by browser.entries.collectAsStateWithLifecycle()
    val downloads by queue.library.collectAsStateWithLifecycle()
    val onDevice = downloads.finished.map { it.id }.toSet()
    val active = downloads.pending
    val scope = rememberCoroutineScopeCompat()

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
                    onOpen = {
                        // `offline-downloads`: an already-downloaded publication is not
                        // re-fetched. It opens from disk, which also means it opens with no
                        // network at all.
                        val local = queue.downloaded(entry)
                        if (local != null) {
                            scope.launch {
                                runCatching { PublicationIndexer.index(local, entry.series) }
                                    .getOrNull()
                                    ?.let { onOpen(it, local.absolutePath) }
                            }
                            return@CatalogueEntryCell
                        }
                        val best = CatalogueAcquisition.best(entry) ?: return@CatalogueEntryCell
                        scope.launch { openWhenReady(queue, entry, best, onOpen) }
                    },
                    onChoose = { link ->
                        scope.launch { openWhenReady(queue, entry, link, onOpen) }
                    },
                    // `offline-downloads`: "the app SHALL let a user download any
                    // publication from a remote source for offline reading". Tapping opens
                    // it, which downloads it as a side effect; a reader packing for a
                    // flight wants the download without the reading.
                    onDownload = {
                        val best = CatalogueAcquisition.best(entry) ?: return@CatalogueEntryCell
                        queue.enqueue(entry, best)
                    },
                    onRemove = { queue.remove(entry.id) },
                )
                // The next page arrives because the reader scrolled, not because they
                // pressed anything.
                LaunchedEffect(index, entries.size) { browser.loadMore(index) }
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
                        if (entries.isEmpty() && feed?.navigation.isNullOrEmpty()) {
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

/** A section, with its count where the feed gave one. */
@Composable
private fun CatalogueSectionRow(section: OpdsSection, onEnter: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Surface(
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.lg),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onEnter),
    ) {
        Column(modifier = Modifier.padding(StoryArcSpace.md)) {
            Text(
                text = section.title,
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            section.count?.let { count ->
                Text(
                    text = pluralStringResource(R.plurals.catalogue_section_count, count, count),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        }
    }
}

/**
 * One publication in a catalogue, before it is on the device.
 *
 * `opds-catalog` requires an entry offering only unsupported formats to be "listed but
 * marked unreadable, naming the formats offered", which is a state a local publication never
 * has.
 */
// `combinedClickable` is still experimental and is the only way to have a tap and a long
// press on one surface. Opted in here, where the long press is the menu.
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CatalogueEntryCell(
    entry: OpdsEntry,
    credential: app.storyarc.core.catalogue.OpdsCredential?,
    /** The page's client, not one of this cell's own. */
    client: OpdsClient,
    /** Whether this one is already on the device. */
    isDownloaded: Boolean,
    onOpen: () -> Unit,
    onChoose: (OpdsAcquisition) -> Unit,
    onDownload: () -> Unit,
    onRemove: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val offered = CatalogueAcquisition.readable(entry)
    var choosing by remember { mutableStateOf(false) }
    var cover by remember(entry.id) { mutableStateOf<android.graphics.Bitmap?>(null) }

    // Fetched through the same client the feed came from: a private catalogue's covers sit
    // behind the same credential, and an image loader has nowhere to put one.
    LaunchedEffect(entry.id) {
        val href = entry.thumbnail ?: entry.cover ?: return@LaunchedEffect
        val bytes = runCatching { client.bytes(href, credential) }.getOrNull()
            ?: return@LaunchedEffect
        cover = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    }

    val describes = subtitle(entry, offered)
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .combinedClickable(
                enabled = offered.isNotEmpty(),
                onClick = { if (offered.size > 1) choosing = true else onOpen() },
                // A long press is where Android puts "what else can I do with this",
                // matching the context menu iOS offers on the same gesture.
                onLongClick = { choosing = true },
            )
            // Merged and named. `Modifier.clickable` makes a node a screen reader can reach
            // and does not pull the title into it, so every cell announced itself as an
            // unnamed button — which `pnpm a11y:android` found and a screenshot could not.
            .semantics(mergeDescendants = true) {
                contentDescription = listOf(entry.title, describes)
                    .filter { it.isNotEmpty() }
                    .joinToString(". ")
            },
    ) {
        Surface(
            color = palette.surfaceRaised,
            shape = RoundedCornerShape(StoryArcRadius.md),
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
        ) {
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(StoryArcRadius.md)),
                )
            } else {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = entry.title,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.textSecondary,
                        textAlign = TextAlign.Center,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
                    )
                }
            }
        }

        // `offline-downloads`: a downloaded publication shows "a state indicator" rather
        // than an action to download it again.
        if (isDownloaded) {
            Text(
                text = stringResource(R.string.catalogue_entry_downloaded),
                style = MaterialTheme.typography.labelSmall,
                color = palette.accent,
            )
        }

        Text(
            text = entry.title,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = subtitle(entry, offered),
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        // `opds-catalog`: the app picks the best format and "lets the user choose another".
        // There is no detail screen yet, so the choice lives here.
        DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }) {
            if (isDownloaded) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.downloads_remove)) },
                    onClick = {
                        choosing = false
                        onRemove()
                    },
                )
            } else {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.catalogue_acquire_download)) },
                    onClick = {
                        choosing = false
                        onDownload()
                    },
                )
            }

            offered.forEach { link ->
                DropdownMenuItem(
                    text = {
                        Text(
                            stringResource(
                                R.string.catalogue_acquire_other,
                                PublicationFormat.ofMediaType(link.mediaType)?.displayName
                                    ?: link.mediaType,
                            ),
                        )
                    },
                    onClick = {
                        choosing = false
                        onChoose(link)
                    },
                )
            }
        }
    }
}

/** The author, or -- when nothing here can be opened -- what was offered instead. */
@Composable
private fun subtitle(entry: OpdsEntry, offered: List<OpdsAcquisition>): String {
    if (offered.isNotEmpty()) {
        val series = entry.series
        val index = entry.seriesIndex
        return when {
            series != null && index != null -> "$series #${index.toInt()}"
            series != null -> series
            else -> entry.authors.firstOrNull().orEmpty()
        }
    }
    val types = entry.acquisitions.map { it.mediaType }.filter { it.isNotEmpty() }.distinct()
    return if (types.isEmpty()) {
        stringResource(R.string.catalogue_entry_no_download)
    } else {
        stringResource(R.string.catalogue_entry_unreadable, types.sorted().joinToString(", "))
    }
}

/** `rememberCoroutineScope`, named so the import list stays legible. */
@Composable
private fun rememberCoroutineScopeCompat() = androidx.compose.runtime.rememberCoroutineScope()

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

/**
 * Waits for a download and opens it.
 *
 * Separate from the tap so the tap returns immediately: `offline-downloads` wants a
 * publication that is still downloading to be openable, and a handler that blocks is a
 * handler nothing else can happen during.
 */
private suspend fun openWhenReady(
    queue: DownloadQueue,
    entry: OpdsEntry,
    link: OpdsAcquisition,
    onOpen: (Publication, String) -> Unit,
) {
    val file = queue.fetch(entry, link) ?: return
    runCatching { PublicationIndexer.index(file, entry.series) }
        .getOrNull()
        ?.let { onOpen(it, file.absolutePath) }
}

/**
 * What the queue is doing, along the foot of the catalogue.
 *
 * One line for the download at the front and a count for the rest, because a reader browsing
 * a catalogue wants to keep browsing -- a list of six transfers belongs in Settings, not over
 * the grid they are reading.
 */
@Composable
private fun DownloadBanner(
    download: Download,
    others: Int,
    onCancel: () -> Unit,
    onResume: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val failed = download.state as? Download.State.Failed
    val paused = download.state as? Download.State.Paused

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.surfaceRaised)
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = when {
                    failed != null -> failed.reason
                    paused != null -> stringResource(R.string.downloads_paused_title, download.title)
                    else -> stringResource(R.string.catalogue_acquire_fetching, download.title)
                },
                style = MaterialTheme.typography.bodySmall,
                color = palette.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (others > 0) {
                Text(
                    text = pluralStringResource(R.plurals.downloads_queued, others, others),
                    style = MaterialTheme.typography.labelSmall,
                    color = palette.textSecondary,
                )
            }
        }

        // One button, and which one depends on what would help. Two on a strip this size is
        // a strip nobody can hit either half of.
        if (failed != null || paused != null) {
            TextButton(onClick = onResume) { Text(stringResource(R.string.downloads_retry)) }
        } else {
            TextButton(onClick = onCancel) { Text(stringResource(R.string.downloads_stop)) }
        }
    }
}
