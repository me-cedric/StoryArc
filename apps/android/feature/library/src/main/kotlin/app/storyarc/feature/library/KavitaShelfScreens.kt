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
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
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
import app.storyarc.core.designsystem.grid.rememberCoverColumns
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
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ShelfEditStore
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
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
            columns = rememberCoverColumns(),
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

    // The order this device has given the list and the server has not taken yet. Read from
    // the same queue a failed position waits in. Empty means the server holds the reader's
    // order already, which is the ordinary case.
    var wanted by remember(listId) { mutableStateOf<List<Int>>(emptyList()) }

    // The push this screen started last, so the next one waits for it. Kavita moves an entry
    // by position, and a position only means anything against the order the server is in. Two
    // moves a second apart would otherwise plan against the same read and land interleaved,
    // leaving the list in an order nobody asked for.
    var pushing by remember(listId) { mutableStateOf<Job?>(null) }

    LaunchedEffect(listId) {
        wanted = KavitaSync.wantedOrder(KavitaProgressStore.open(context), server.id, listId)
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
    // The server's entries in the reader's order, with the outstanding ones after them.
    // ShelfSync and ShelfMerge decide both orders, so a test can assert them without a server.
    val rows = ShelfMerge.projecting(
        remote = ShelfSync.arranged(
            items.map { ShelfEntry(it.chapterId.toString(), it.displayName, false) },
            wanted.map { it.toString() },
        ),
        pending = pending,
    )

    // Applies a move, and owes the server the order it produced. The rows move first and the
    // send is attempted after, which is the order `collections-and-reading-lists` asks for --
    // the edit is "applied locally, marked pending, and pushed on reconnection".
    // KavitaSync.reorder writes it down before it tries, so a refused send is a queue entry
    // rather than a lost order.
    fun move(from: Int, to: Int) {
        val held = rows.filterNot { it.isPending }.map { it.id }
        if (from !in held.indices || to !in held.indices) return
        val next = held.toMutableList().apply { add(to, removeAt(from)) }
        val order = next.mapNotNull { it.toIntOrNull() }
        items = order.mapNotNull { id -> items.firstOrNull { it.chapterId == id } } +
            items.filterNot { it.chapterId in order }
        val previous = pushing
        pushing = scope.launch {
            previous?.join()
            val store = KavitaProgressStore.open(context)
            KavitaSync.reorder(store, server.address, server.id, listId, order)
            wanted = KavitaSync.wantedOrder(store, server.id, listId)
        }
    }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = { ShelfBar(title, onBack) },
    ) { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
        ) {
            if (wanted.isNotEmpty()) {
                // `collections-and-reading-lists` wants a pending edit "visible on the list".
                // An order is one edit about every row, so it is said once, above them.
                item {
                    Text(
                        text = stringResource(R.string.shelves_pending_order),
                        style = MaterialTheme.typography.bodySmall,
                        color = StoryArcColor.Status.offline,
                    )
                }
            }
            itemsIndexed(rows, key = { _, row -> row.id }) { index, row ->
                val entry = items.firstOrNull { it.chapterId.toString() == row.id }
                val held = rows.count { !it.isPending }
                EntryRow(
                    row = row,
                    number = index + 1,
                    series = entry?.seriesName?.takeIf { it != row.title },
                    isFetching = fetching?.toString() == row.id,
                    // An entry the server has not heard of has no place in the server's own
                    // order, so it cannot be moved into one.
                    canMoveUp = !row.isPending && index > 0,
                    canMoveDown = !row.isPending && index + 1 < held,
                    onUp = { move(index, index - 1) },
                    onDown = { move(index, index + 1) },
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
    TopAppBar(
        title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.catalogue_back),
                    tint = MaterialTheme.colorScheme.primary,
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
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onUp: () -> Unit,
    onDown: () -> Unit,
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
        // Two buttons rather than a drag, which is what a local reading list already offers
        // here: the same control on both of this platform's reading lists beats matching the
        // other platform on one of them.
        IconButton(onClick = onUp, enabled = canMoveUp) {
            Icon(
                Icons.Filled.ArrowUpward,
                contentDescription = stringResource(R.string.shelves_move_up, row.title),
                tint = palette.textSecondary,
            )
        }
        IconButton(onClick = onDown, enabled = canMoveDown) {
            Icon(
                Icons.Filled.ArrowDownward,
                contentDescription = stringResource(R.string.shelves_move_down, row.title),
                tint = palette.textSecondary,
            )
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
