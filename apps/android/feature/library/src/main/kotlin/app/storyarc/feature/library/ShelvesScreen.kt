package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import androidx.compose.foundation.lazy.LazyListScope
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaCollection
import app.storyarc.core.kavita.KavitaReadingList
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin
import java.util.UUID

/**
 * Collections and reading lists, in one place.
 *
 * `collections-and-reading-lists` requires local and server groupings to appear "in one
 * list, each labelled with its source" rather than segregated. Two sections here because
 * they are two different ideas, not two different origins -- the origin is a label on a row.
 *
 * iOS's `ShelvesView` is the same screen.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun ShelvesScreen(
    viewModel: LibraryViewModel,
    onOpenCollection: (UUID) -> Unit,
    onOpenList: (UUID) -> Unit,
    onBack: () -> Unit,
    /** The Kavita servers whose own shelves belong here too. */
    servers: List<KavitaPage> = emptyList(),
    onOpenServerCollection: (KavitaPage, Int, String) -> Unit = { _, _, _ -> },
    onOpenServerList: (KavitaPage, Int, String) -> Unit = { _, _, _ -> },
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val registry by viewModel.registry.collectAsStateWithLifecycle()

    // Fetched here rather than per row: `collections-and-reading-lists` wants a server's
    // collections "alongside local ones", which means inside the same two sections, and a
    // section cannot be built from rows that each fetch their own.
    var serverShelves by remember { mutableStateOf<List<ServerShelf>>(emptyList()) }
    LaunchedEffect(servers) {
        serverShelves = servers.flatMap { server ->
            val client = KavitaClient(server.address)
            val collections = runCatching { client.collections() }.getOrDefault(emptyList())
            val lists = runCatching { client.readingLists() }.getOrDefault(emptyList())
            collections.map { ServerShelf(server, it.id, it.title, isList = false) } +
                lists.map { ServerShelf(server, it.id, it.title, isList = true) }
        }
    }

    var creating by remember { mutableStateOf<Boolean?>(null) }
    var draft by remember { mutableStateOf("") }
    var menuOpen by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.shelves_title)) },
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
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(
                            imageVector = Icons.Filled.Add,
                            contentDescription = stringResource(R.string.shelves_new),
                            tint = palette.accent,
                        )
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.shelves_new_collection)) },
                            onClick = {
                                menuOpen = false
                                draft = ""
                                creating = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.shelves_new_list)) },
                            onClick = {
                                menuOpen = false
                                draft = ""
                                creating = true
                            },
                        )
                    }
                },
            )
        },
    ) { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            item {
                Text(
                    text = stringResource(R.string.shelves_collections),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                )
            }
            val serverCollections = serverShelves.filterNot { it.isList }
            if (shelves.collections.isEmpty() && serverCollections.isEmpty()) {
                item { Blurb(stringResource(R.string.shelves_collections_none)) }
            } else {
                items(shelves.collections, key = { it.id }) { collection ->
                    ShelfRow(
                        name = collection.name,
                        count = collection.members.size,
                        source = collection.origin.sourceName(registry.sources),
                        onOpen = { onOpenCollection(collection.id) },
                        onDelete = { viewModel.deleteCollection(collection.id) },
                    )
                }
                items(serverCollections, key = { "c-${it.server.id}-${it.id}" }) { shelf ->
                    ShelfRow(
                        name = shelf.title,
                        count = null,
                        source = shelf.server.title,
                        onOpen = { onOpenServerCollection(shelf.server, shelf.id, shelf.title) },
                        onDelete = null,
                    )
                }
            }

            item {
                Text(
                    text = stringResource(R.string.shelves_lists),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                    modifier = Modifier.padding(top = StoryArcSpace.md),
                )
            }
            val serverLists = serverShelves.filter { it.isList }
            if (shelves.lists.isEmpty() && serverLists.isEmpty()) {
                item { Blurb(stringResource(R.string.shelves_lists_none)) }
            } else {
                items(shelves.lists, key = { it.id }) { list ->
                    ShelfRow(
                        name = list.name,
                        count = list.entries.size,
                        source = list.origin.sourceName(registry.sources),
                        onOpen = { onOpenList(list.id) },
                        onDelete = { viewModel.deleteList(list.id) },
                    )
                }
                items(serverLists, key = { "l-${it.server.id}-${it.id}" }) { shelf ->
                    ShelfRow(
                        name = shelf.title,
                        count = null,
                        source = shelf.server.title,
                        onOpen = { onOpenServerList(shelf.server, shelf.id, shelf.title) },
                        onDelete = null,
                    )
                }
            }
        }
    }

    creating?.let { isList ->
        AlertDialog(
            onDismissRequest = { creating = null },
            title = {
                Text(
                    stringResource(
                        if (isList) R.string.shelves_new_list else R.string.shelves_new_collection,
                    ),
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                    // `collections-and-reading-lists`: "the storage location is stated at
                    // creation, not discovered later". There is one location today, and
                    // saying so is what makes the sentence true rather than unfalsified.
                    Text(stringResource(R.string.shelves_new_stored_locally))
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = { Text(stringResource(R.string.shelves_new_field)) },
                        singleLine = true,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (isList) viewModel.createList(draft) else viewModel.createCollection(draft)
                    creating = null
                }) {
                    Text(stringResource(R.string.shelves_create))
                }
            },
            dismissButton = {
                TextButton(onClick = { creating = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

@Composable
private fun Blurb(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = LocalStoryArcPalette.current.textSecondary,
    )
}

@Composable
private fun ShelfRow(
    name: String,
    count: Int?,
    source: String?,
    onOpen: () -> Unit,
    // Null for a server's own shelf. Deleting one is the server's business, and a bin icon
    // that only ever failed would be worse than no bin icon.
    onDelete: (() -> Unit)?,
) {
    val palette = LocalStoryArcPalette.current
    val items = count?.let { pluralStringResource(R.plurals.shelves_count, it, it) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyLarge, color = palette.textPrimary)
            val subtitle = listOfNotNull(source, items).joinToString(" · ")
            if (subtitle.isNotEmpty()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        }
        if (onDelete != null) {
            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.shelves_delete, name),
                    tint = palette.textSecondary,
                )
            }
        }
    }
}

/** The name of the source a grouping came from, when it came from one. */
private fun ShelfOrigin.sourceName(sources: List<app.storyarc.core.model.Source>): String? =
    sourceId?.let { id -> sources.firstOrNull { it.id == id }?.displayName }

/** Kept so the file's two public entry points sit beside their model types. */
internal typealias Collection = PublicationCollection

/** Same. */
internal typealias Listing = ReadingList

/**
 * One of a server's own shelves.
 *
 * A collection and a reading list differ in kind -- one groups series with no order, the
 * other is an ordered run of chapters -- so the flag chooses the screen rather than one
 * screen guessing from what it finds.
 */
data class ServerShelf(
    val server: KavitaPage,
    val id: Int,
    val title: String,
    val isList: Boolean,
)
