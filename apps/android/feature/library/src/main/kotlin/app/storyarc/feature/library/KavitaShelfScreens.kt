package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ShelfEntry
import app.storyarc.core.model.ShelfKey
import app.storyarc.core.model.ShelfMerge
import app.storyarc.core.persistence.ShelfEditStore
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The series in one of a server's collections.
 *
 * A collection groups series and has no order, so this is the same grid of covers a library
 * uses rather than the numbered run a reading list needs.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun KavitaCollectionScreen(
    server: KavitaPage,
    collectionId: Int,
    title: String,
    onOpenSeries: (KavitaSeries) -> Unit,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val client = remember(server.address) { KavitaClient(server.address) }
    var series by remember(collectionId) { mutableStateOf<List<KavitaSeries>>(emptyList()) }

    LaunchedEffect(collectionId) {
        series = runCatching { client.collected(collectionId) }.getOrDefault(emptyList())
    }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = { ShelfBar(title, onBack) },
    ) { insets ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 140.dp),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            modifier = Modifier.fillMaxSize().padding(insets),
        ) {
            items(series, key = { it.id }) { each ->
                KavitaSeriesCell(each, client) { onOpenSeries(each) }
            }
        }
    }
}

/**
 * The entries in one of a server's reading lists, in the server's order.
 *
 * Numbered, because the order is the point. A collection has none and this does.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun KavitaListScreen(
    server: KavitaPage,
    listId: Int,
    title: String,
    onOpen: (Publication, String) -> Unit,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val client = remember(server.address) { KavitaClient(server.address) }
    var items by remember(listId) { mutableStateOf<List<KavitaReadingListItem>>(emptyList()) }
    var fetching by remember(listId) { mutableStateOf<Int?>(null) }

    LaunchedEffect(listId) {
        items = runCatching { client.readingListItems(listId) }
            .getOrDefault(emptyList())
            .sortedBy { it.order }
    }

    // Edits this device has made that the server has not taken yet.
    //
    // `collections-and-reading-lists` requires an edit made while the server was unreachable
    // to be "applied locally" and its pending state to be "visible on the list".
    val pending = remember(listId, items) {
        ShelfEditStore.open(context).queue().pending(ShelfKey(server.id, listId))
    }
    // The server's entries, with the outstanding ones after them. ShelfMerge decides the
    // order, so a test can assert it without a server.
    val rows = ShelfMerge.projecting(
        remote = items.map { ShelfEntry(it.chapterId.toString(), it.displayName, false) },
        pending = pending,
    )

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = { ShelfBar(title, onBack) },
    ) { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
        ) {
            itemsIndexed(rows, key = { _, row -> row.id }) { index, row ->
                val entry = items.firstOrNull { it.chapterId.toString() == row.id }
                EntryRow(
                    row = row,
                    number = index + 1,
                    series = entry?.seriesName?.takeIf { it != row.title },
                    isFetching = fetching?.toString() == row.id,
                ) {
                    if (entry == null) return@EntryRow
                    scope.launch {
                        fetching = entry.chapterId
                        fetchEntry(context, client, entry)?.let { (publication, path) ->
                            onOpen(publication, path)
                        }
                        fetching = null
                    }
                }
            }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun ShelfBar(title: String, onBack: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    TopAppBar(
        title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.catalogue_back),
                    tint = palette.accent,
                )
            }
        },
    )
}

@Composable
private fun EntryRow(
    row: ShelfEntry,
    number: Int,
    series: String?,
    isFetching: Boolean,
    onOpen: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            // A pending entry cannot be opened from here: the server is what would hand the
            // file over, and it has not heard of this entry yet.
            .clickable(enabled = !isFetching && !row.isPending, onClick = onOpen)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs),
    ) {
        Text(
            text = "$number",
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = row.title,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.textPrimary,
            )
            if (row.isPending) {
                // Grey rather than red: an unsent edit is offline, and `sources` makes
                // offline a normal state.
                Text(
                    text = stringResource(R.string.shelves_pending_entry),
                    style = MaterialTheme.typography.bodySmall,
                    color = StoryArcColor.Status.offline,
                )
            } else {
                series?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.textSecondary,
                    )
                }
            }
        }
        if (isFetching) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(2.dp))
        }
    }
}

/** Fetches one entry's chapter and indexes it, the way the chapter list does. */
private suspend fun fetchEntry(
    context: android.content.Context,
    client: KavitaClient,
    entry: KavitaReadingListItem,
): Pair<Publication, String>? = runCatching {
    val fetched = client.chapter(entry.chapterId)
    val file = withContext(Dispatchers.IO) {
        kavitaCacheFile(context, entry.chapterId, fetched.mediaType)
            .apply { writeBytes(fetched.bytes) }
    }
    PublicationIndexer.index(file, catalogueSeries = entry.seriesName) to file.absolutePath
}.getOrNull()
