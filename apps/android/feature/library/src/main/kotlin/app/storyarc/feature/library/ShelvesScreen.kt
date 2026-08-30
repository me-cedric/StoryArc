package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfEditQueue
import app.storyarc.core.model.ShelfOrigin
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ShelfEditStore
import java.util.UUID

/**
 * Collections and reading lists, in one place.
 *
 * `collections-and-reading-lists` requires local and server groupings to appear "in one
 * list, each labelled with its source" rather than segregated. Two sections here because
 * they are two different ideas, not two different origins -- the origin is a label on a row.
 *
 * Drawn as two shelves of covers rather than two lists of names. §3.6 of the revamp: "a
 * collection with no artwork is a folder listing", and a folder listing is the one thing this
 * app is not. Each section leads with the sentence that says what its shelves *are*, because
 * *collection* and *reading list* are words a reader has to be taught once.
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

    // Edits owed to a server, so a shelf can say so and a conflict can be said once. Read into
    // the screen rather than asked for per card: the badge and the notice come out of the same
    // reconciliation, and a card that fetched its own would disagree with the dialogue above.
    val context = LocalContext.current
    val edits = remember(context) { ShelfEditStore.open(context) }
    val progress = remember(context) { KavitaProgressStore.open(context) }
    var queue by remember { mutableStateOf(ShelfEditQueue()) }

    LaunchedEffect(serverShelves) {
        // Asks every server list what it holds, settles what has landed, and pushes what has
        // not -- the "on reconnection" half of the offline rule, driven by the one moment
        // this screen already knows a server answered.
        //
        // The queue is read either way. What is owed, and what is still to be said about a
        // conflict, are worth showing when no server answers at all -- which is exactly the
        // state the reader most wants an answer about.
        ShelfSync.reconcile(serverShelves.filter { it.isList }, edits, progress)
        queue = edits.queue()
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
        val finished = viewModel.finishedPublications()

        LazyVerticalGrid(
            // Both bounds for the reason `CoverGrid` gives, and a wider minimum than a
            // publication's: a shelf is a composite of four covers, and four covers below
            // about 150 dp stop being four covers.
            columns = BoundedAdaptive(SHELF_MINIMUM_WIDTH, SHELF_MAXIMUM_WIDTH),
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
        ) {
            val serverCollections = serverShelves.filterNot { it.isList }
            heading(R.string.shelves_collections, R.string.shelves_collections_about)

            if (shelves.collections.isNotEmpty() || serverCollections.isNotEmpty()) {
                items(shelves.collections, key = { it.id }) { collection ->
                    // `collections-and-reading-lists` gives a collection with contents a
                    // cover "composite of its first four member covers", and the artwork is
                    // the interface.
                    ShelfCard(
                        viewModel = viewModel,
                        title = collection.name,
                        subtitle = caption(collection.origin, collection.members.size, registry.sources),
                        tiles = shelfTiles(collection),
                        onOpen = { onOpenCollection(collection.id) },
                        onDelete = { viewModel.deleteCollection(collection.id) },
                    )
                }
                items(serverCollections, key = { "c-${it.server.id}-${it.id}" }) { shelf ->
                    ServerShelfCard(viewModel, shelf) {
                        onOpenServerCollection(shelf.server, shelf.id, shelf.title)
                    }
                }
            }

            val serverLists = serverShelves.filter { it.isList }
            heading(R.string.shelves_lists, R.string.shelves_lists_about)

            if (shelves.lists.isNotEmpty() || serverLists.isNotEmpty()) {
                items(shelves.lists, key = { it.id }) { list ->
                    // A list's tiles are its first four entries in *its* order, and its rail
                    // is how far through that order the reader is -- the two things that make
                    // it a list rather than a bag.
                    ShelfCard(
                        viewModel = viewModel,
                        title = list.name,
                        subtitle = caption(list.origin, list.entries.size, registry.sources),
                        tiles = shelfTiles(list),
                        onOpen = { onOpenList(list.id) },
                        progress = shelfFraction(list, finished),
                        onDelete = { viewModel.deleteList(list.id) },
                    )
                }
                items(serverLists, key = { "l-${it.server.id}-${it.id}" }) { shelf ->
                    ServerShelfCard(
                        viewModel = viewModel,
                        shelf = shelf,
                        pending = queue.pending(ShelfSync.key(shelf)).size,
                    ) {
                        onOpenServerList(shelf.server, shelf.id, shelf.title)
                    }
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

    // `collections-and-reading-lists`: on a conflict "the user is told once what changed".
    // Dismissing it is what makes it once -- the notice is deleted, not hidden, so the next
    // refresh has nothing left to raise.
    queue.nextNotice?.let { notice ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.shelves_conflict_title)) },
            text = {
                Text(
                    stringResource(
                        R.string.shelves_conflict_body,
                        notice.shelfName,
                        notice.discarded.joinToString(", "),
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    edits.update { it.acknowledging(notice.id) }
                    queue = edits.queue()
                }) {
                    Text(stringResource(R.string.shelves_conflict_understood))
                }
            },
        )
    }
}

/** The narrowest a composite of four covers still reads as four covers. */
private val SHELF_MINIMUM_WIDTH = 150.dp

/** And the widest, so a tablet gets more shelves rather than enormous ones. */
private val SHELF_MAXIMUM_WIDTH = 220.dp

/**
 * A section's name and the one sentence that says what its shelves are.
 *
 * §3.6 asks for Komga's metaphor in the copy -- a collection groups what you like, a reading
 * list is a playlist for books. Above the shelf rather than only in the empty state, because
 * the reader who has never met the word is not always the reader who has none of them --
 * and it *is* the empty state, because a second sentence saying there are none of something
 * the line above has just defined tells the reader nothing the blank space below it does not.
 */
private fun LazyGridScope.heading(title: Int, about: Int) {
    item(span = { GridItemSpan(maxLineSpan) }) {
        Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
            Text(
                text = stringResource(title),
                style = MaterialTheme.typography.titleMedium,
                color = LocalStoryArcPalette.current.textPrimary,
            )
            Text(
                text = stringResource(about),
                style = MaterialTheme.typography.bodySmall,
                color = LocalStoryArcPalette.current.textSecondary,
            )
        }
    }
}

/**
 * A shelf that lives in an online library.
 *
 * No composite: its members are chapters on a server this device has not necessarily opened,
 * so there is no local artwork to compose from and a half-loaded mosaic would be worse than a
 * clean blank.
 */
@Composable
private fun ServerShelfCard(
    viewModel: LibraryViewModel,
    shelf: ServerShelf,
    pending: Int = 0,
    onOpen: () -> Unit,
) {
    ShelfCard(
        viewModel = viewModel,
        title = shelf.title,
        subtitle = shelf.server.title,
        tiles = emptyList(),
        onOpen = onOpen,
        pending = pending,
    )
}

/** Where the grouping came from, and how much is in it. */
@Composable
private fun caption(origin: ShelfOrigin, count: Int, sources: List<Source>): String {
    val items = pluralStringResource(R.plurals.shelves_count, count, count)
    val source = origin.sourceName(sources) ?: return items
    return "$source · $items"
}

/**
 * How far through a reading list the reader is.
 *
 * [ReadingList.position] counts it, so the rail on the card and the line inside the list can
 * never disagree about where the reader is.
 */
internal fun shelfFraction(list: ReadingList, finished: Set<String>): Float {
    if (list.entries.isEmpty()) return 0f
    return list.position { it in finished }.toFloat() / list.entries.size
}

/** The name of the source a grouping came from, when it came from one. */
private fun ShelfOrigin.sourceName(sources: List<Source>): String? =
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
