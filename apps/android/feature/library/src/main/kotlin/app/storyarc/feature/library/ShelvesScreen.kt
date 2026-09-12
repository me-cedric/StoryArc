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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.grid.BoundedAdaptive
import app.storyarc.core.designsystem.grid.steppedForFontScale
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.CompositeCover
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.RememberedShelf
import app.storyarc.core.model.ShelfEditQueue
import app.storyarc.core.model.ShelfOrigin
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.ShelfEditStore
import java.util.UUID
import kotlinx.coroutines.launch

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
    /** Where a pin is written down. Null in a preview and in a test that does not care. */
    preferences: LibraryPreferences? = null,
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val registry by viewModel.registry.collectAsStateWithLifecycle()

    // Which shelves the reader put on the home surface. Held here and written through on
    // every change rather than on the way out: this screen has no moment it could call the
    // way out, for the reason `LibraryScreen` gives about its own choices.
    //
    // Beside the shelves rather than inside them -- `home-screen` requires unpinning to leave
    // "the collection or the list" untouched, and a pin stored in a shelf's own record would
    // be one server pull away from breaking that. `PinnedShelves` argues it at length.
    // `remember` and not `rememberSaveable`: every change is written through below, so the
    // store is the source of truth and a re-initialisation after process death reads the
    // truth rather than a stale copy of it. A saver would be a second answer to the same
    // question -- which is the failure `LibraryScreen`'s availability note describes from
    // the other side, where the saver earns its place by carrying a choice the store has not
    // been asked for yet.
    var pinned by remember(preferences) {
        mutableStateOf(PinnedShelves.of(preferences?.pinnedShelves().orEmpty()))
    }
    val togglePin: (ShelfPin) -> Unit = { pin ->
        pinned = pinned.toggling(pin)
        preferences?.savePinnedShelves(pinned.tokens)
    }

    // Fetched here rather than per row: `collections-and-reading-lists` wants a server's
    // collections "alongside local ones", which means inside the same two sections, and a
    // section cannot be built from rows that each fetch their own.
    var serverShelves by remember { mutableStateOf<List<ServerShelf>>(emptyList()) }
    // Which of those servers could take a new shelf, per kind. `collections-and-reading-lists`
    // offers a server at creation only when it "supports" the kind being made, and a server
    // that has just answered is the only honest reading of that -- an empty answer and no
    // answer are different things.
    var collectionCapable by remember { mutableStateOf<List<KavitaPage>>(emptyList()) }
    var listCapable by remember { mutableStateOf<List<KavitaPage>>(emptyList()) }
    LaunchedEffect(servers) {
        val found = mutableListOf<ServerShelf>()
        val holdsCollections = mutableListOf<KavitaPage>()
        val holdsLists = mutableListOf<KavitaPage>()
        for (server in servers) {
            val client = KavitaClient(server.address)
            runCatching { client.collections() }.getOrNull()?.let { collections ->
                holdsCollections += server
                found += collections.map {
                    // A collection carries the same locked-cover flag a reading list does. It
                    // was read for the list and dropped for the collection until 2026-09-12,
                    // so a reader who chose a collection's cover on the server was shown the
                    // app's composite instead.
                    ServerShelf(server, it.id, it.title, isList = false, chosenCover = it.coverImageLocked)
                }
            }
            runCatching { client.readingLists() }.getOrNull()?.let { lists ->
                holdsLists += server
                found += lists.map {
                    ServerShelf(server, it.id, it.title, isList = true, chosenCover = it.coverImageLocked)
                }
            }
        }
        serverShelves = found
        collectionCapable = holdsCollections
        listCapable = holdsLists
        // Written down, because the home surface may not ask a server anything and this is the
        // only moment anything asks one. `home-screen` requires that surface to render with
        // "the same shelves in the same order as when the sources are up", so a server's
        // collection can only reach it as a memory -- see `RememberedShelf`.
        //
        // Replaced rather than merged: this pass asked every configured server, so `found` is
        // the complete set and a merge would only keep shelves deleted on a server since.
        // Skipped when no server *answered*, which is the offline case -- and answering with
        // nothing is not the same thing as not answering, so the test is the capability lists
        // rather than `found`. A reader who opens this screen on a train must not lose every
        // name the home surface had.
        if (holdsCollections.isNotEmpty() || holdsLists.isNotEmpty()) {
            preferences?.saveRememberedShelves(
                RememberedShelf.tokens(HomeShelfIndex.remembering(found)),
            )
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

    val scope = rememberCoroutineScope()
    var creating by remember { mutableStateOf<Boolean?>(null) }
    var draft by remember { mutableStateOf("") }
    /** Set when a server would not take the shelf the reader asked it to keep. */
    var serverRefusedTheShelf by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }

    // The shelf a reader has asked to delete and not yet answered for.
    // `collections-and-reading-lists`: deleting a collection is confirmed, and the confirmation
    // "states plainly that the publications themselves are not deleted". This is the gap between
    // the two -- while it holds something, nothing has been written.
    var deleting by remember { mutableStateOf<ShelfDeletion?>(null) }

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
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(
                            imageVector = Icons.Filled.Add,
                            contentDescription = stringResource(R.string.shelves_new),
                            tint = MaterialTheme.colorScheme.primary,
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

        // The lattice's own floor and cap, one accessibility step wider past the ordinary
        // range — `design.md` §4. A shelf of four covers wants a wider floor than one cover
        // does; it does not want to be the one grid in the app that ignores the text size.
        val fontScale = LocalDensity.current.fontScale
        LazyVerticalGrid(
            // Both bounds for the reason `CoverGrid` gives, and a wider minimum than a
            // publication's: a shelf is a composite of four covers, and four covers below
            // about 150 dp stop being four covers.
            columns = remember(fontScale) {
                BoundedAdaptive(
                    shelfLatticeMinimumWidth(fontScale),
                    shelfLatticeMaximumWidth(fontScale),
                )
            },
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
        ) {
            val serverCollections = serverShelves.filterNot { it.isList }
            heading(R.string.shelves_collections, R.string.shelves_collections_about)

            if (shelves.collections.isEmpty() && serverCollections.isEmpty()) {
                makeShelfButton(R.string.shelves_new_collection) {
                    draft = ""
                    creating = false
                }
            }

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
                        onDelete = { deleting = ShelfDeletion.of(collection) },
                        isPinned = ShelfPin.Collection(collection.id) in pinned,
                        onTogglePin = { togglePin(ShelfPin.Collection(collection.id)) },
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

            if (shelves.lists.isEmpty() && serverLists.isEmpty()) {
                makeShelfButton(R.string.shelves_new_list) {
                    draft = ""
                    creating = true
                }
            }

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
                        onDelete = { deleting = ShelfDeletion.of(list) },
                        isPinned = ShelfPin.ReadingListPin(list.id) in pinned,
                        onTogglePin = { togglePin(ShelfPin.ReadingListPin(list.id)) },
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
        ShelfCreationDialog(
            draft = ShelfDraft(isList, if (isList) listCapable else collectionCapable),
            name = draft,
            onName = { draft = it },
            onDevice = {
                if (isList) viewModel.createList(draft) else viewModel.createCollection(draft)
                creating = null
            },
            onServer = { page ->
                creating = null
                scope.launch {
                    val made = ShelfCreation.make(isList, draft, page)
                    if (made == null) serverRefusedTheShelf = true else serverShelves += made
                }
            },
            onDismiss = { creating = null },
        )
    }

    // A server that would not take it is said out loud rather than quietly turned into a local
    // shelf: a shelf whose stated home is a lie is worse than an error.
    if (serverRefusedTheShelf) {
        AlertDialog(
            onDismissRequest = { serverRefusedTheShelf = false },
            title = { Text(stringResource(R.string.shelves_new_refused)) },
            confirmButton = {
                TextButton(onClick = { serverRefusedTheShelf = false }) {
                    Text(stringResource(R.string.shelves_conflict_understood))
                }
            },
        )
    }

    deleting?.let { deletion ->
        ShelfDeletionDialog(
            deletion = deletion,
            onConfirm = {
                viewModel.delete(deletion)
                deleting = null
            },
            onDismiss = { deleting = null },
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

/** The narrowest a composite of four covers still reads as four, at an ordinary text size. */
private val SHELF_MINIMUM_WIDTH = 150.dp

/** And the widest, so a tablet gets more shelves rather than enormous ones. */
private val SHELF_MAXIMUM_WIDTH = 220.dp

/**
 * The lattice's floor, one accessibility step wider past the ordinary range: 150 → 210.
 *
 * A floor of its own, because four covers below about 150 dp stop being four covers; the
 * ladder's step, because the caption under a shelf card is the same caption that cramps under
 * a cover. Pure, so `CoverLadderStepTest` can assert it without a screen.
 */
internal fun shelfLatticeMinimumWidth(fontScale: Float): Dp =
    SHELF_MINIMUM_WIDTH.steppedForFontScale(fontScale)

/** The lattice's cap, stepping with its floor so the wider columns are filled: 220 → 308. */
internal fun shelfLatticeMaximumWidth(fontScale: Float): Dp =
    SHELF_MAXIMUM_WIDTH.steppedForFontScale(fontScale)

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
 * What an empty section offers instead of blank space.
 *
 * The sentence stays in [heading] — repeating "no collections yet" under a line that has
 * just explained what a collection *is* tells the reader nothing the blank space does not.
 * What the blank space was missing is the way out: the only way to make a shelf was the plus
 * in the app bar, which is a control a reader has to already know about, on the one screen
 * where they demonstrably do not. iOS grew the same button in `ShelvesView`.
 */
private fun LazyGridScope.makeShelfButton(label: Int, onClick: () -> Unit) {
    item(span = { GridItemSpan(maxLineSpan) }) {
        TextButton(onClick = onClick) {
            Icon(
                imageVector = Icons.Filled.Add,
                contentDescription = null,
                modifier = Modifier.padding(end = StoryArcSpace.xs),
            )
            Text(stringResource(label))
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
    val client = remember(shelf.server.address) { KavitaClient(shelf.server.address) }

    // The ids the composite stands on. `collections-and-reading-lists` wants the first four
    // *members*, and a server names its members only when asked -- so the card reads its own
    // shelf once. A collection is a set of series and a list is an ordered run of chapters,
    // which is why the two ask different routes and load different artwork.
    var tiles by remember(shelf) { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(shelf) {
        tiles = runCatching {
            if (shelf.isList) {
                client.readingListItems(shelf.id)
                    .sortedBy { it.order }
                    .take(CompositeCover.TILE_COUNT)
                    .map { it.chapterId.toString() }
            } else {
                client.collected(shelf.id)
                    .take(CompositeCover.TILE_COUNT)
                    .map { it.id.toString() }
            }
        }.getOrDefault(emptyList())
    }

    ShelfCard(
        viewModel = viewModel,
        title = shelf.title,
        subtitle = shelf.server.title,
        tiles = tiles,
        onOpen = onOpen,
        pending = pending,
        cover = {
            ServerShelfCover(
                name = shelf.title,
                tiles = if (shelf.chosenCover) listOf(SERVER_COVER) else tiles,
                load = { id ->
                    // `coverImageLocked` is the spec's "unless the user sets a specific one",
                    // and each kind of shelf has its own route to the cover it holds.
                    if (id == SERVER_COVER) {
                        if (shelf.isList) client.readingListCover(shelf.id)
                        else client.collectionCover(shelf.id)
                    } else if (shelf.isList) {
                        client.chapterCover(id.toInt())
                    } else {
                        client.seriesCover(id.toInt())
                    }
                },
            )
        },
    )
}

/** The one tile a shelf has when the reader chose its cover on the server. */
private const val SERVER_COVER = "server-cover"

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
    /**
     * Whether a reader chose this shelf's cover on the server.
     *
     * `collections-and-reading-lists` composites the first four members "unless the user sets
     * a specific one", and Kavita's `coverImageLocked` is the server's word for having set
     * one. False -- including for every server too old to send the field -- composites.
     */
    val chosenCover: Boolean = false,
)
