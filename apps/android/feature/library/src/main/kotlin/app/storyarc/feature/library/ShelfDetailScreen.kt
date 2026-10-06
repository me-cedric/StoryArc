package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import java.util.UUID

/**
 * What is in a collection.
 *
 * A grid, because a collection is a shelf and a shelf is looked at rather than worked
 * through. Its reading list counterpart is a list, for the opposite reason.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CollectionDetailScreen(
    viewModel: LibraryViewModel,
    id: UUID,
    /**
     * A cover was chosen: that publication's page.
     *
     * `publication-detail` names a collection as one of the four surfaces a page is
     * reached from — "in the library, in a shelf, in search results or in a collection".
     * Nothing on this screen offers to resume, so there is no second verb here.
     */
    onOpen: (Publication) -> Unit,
    onBack: () -> Unit,
    /** Marks a publication read. The app layer owns the secrets the server may need. */
    onMark: (Publication, Boolean) -> Unit = { _, _ -> },
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val publications by viewModel.publications.collectAsStateWithLifecycle()

    val collection = shelves.collections.firstOrNull { it.id == id }
    val members = publications.filter { it.id in (collection?.members ?: emptySet()) }

    val snackbars = remember { SnackbarHostState() }
    var undo by remember { mutableStateOf<BulkUndo?>(null) }
    BulkUndoEffect(undo, snackbars, viewModel, publications, onMark) { undo = null }

    // Whether the reader is choosing which cover this collection wears.
    var isChoosingCover by remember { mutableStateOf(false) }
    var restarting by remember { mutableStateOf<Publication?>(null) }

    // `library-browsing`'s *A publication's actions wherever it is drawn* named this screen
    // as one of the places that offered none at all. A member can leave the collection it is
    // showing in, which is the one row the library grid never offers.
    val publicationActions = PublicationActionCallbacks(
        onMark = onMark,
        onRestart = { restarting = it },
        onShowDetails = onOpen,
        onRemoveFromShelf = { viewModel.removeFromCollection(setOf(it.id), id) },
    )

    Scaffold(
        containerColor = palette.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
        topBar = {
            DetailBar(collection?.name.orEmpty(), onBack) {
                // `collections-and-reading-lists`: the composite is what a collection wears
                // "unless the user sets a specific one". The offer lives here rather than on
                // the shelf card, because choosing between four covers and one is a question
                // about what is inside the collection, and this is the screen showing what is
                // inside it. A collection holding nothing has nothing to offer, so it does
                // not ask.
                if (collection?.members?.isNotEmpty() == true) {
                    IconButton(onClick = { isChoosingCover = true }) {
                        Icon(
                            imageVector = Icons.Filled.GridView,
                            contentDescription = stringResource(R.string.shelves_cover),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                // `collections-and-reading-lists` asks for a whole collection to be
                // downloaded or marked read. Membership rather than the grid: a publication
                // whose file has gone is still a member, and marking it read is still what
                // the reader asked for.
                ShelfBulkMenu(
                    viewModel = viewModel,
                    members = collection?.members ?: emptySet(),
                    publications = publications,
                    onMark = onMark,
                    onChange = { undo = it },
                )
            }
        },
    ) { insets ->
        Column(modifier = Modifier.fillMaxSize().padding(insets)) {
            if (members.isEmpty()) {
                Text(
                    text = stringResource(R.string.shelves_collection_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                    modifier = Modifier.padding(StoryArcSpace.gutter),
                )
            } else {
                Box(modifier = Modifier.padding(horizontal = StoryArcSpace.gutter)) {
                    ShelfOnDeviceLine(members, location = viewModel::location)
                }
                CoverGrid(
                    publications = members,
                    viewModel = viewModel,
                    continueReading = emptyList(),
                    onOpen = onOpen,
                    actions = publicationActions,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    if (isChoosingCover && collection != null) {
        ShelfCoverPicker(
            viewModel = viewModel,
            subject = ShelfCoverSubject.OfCollection(collection),
            onDismiss = { isChoosingCover = false },
        )
    }

    val restart = restarting
    if (restart != null) {
        RestartConfirmation(
            publication = restart,
            viewModel = viewModel,
            onDismiss = { restarting = null },
        )
    }
}

/**
 * What is in a reading list, in the order it is meant to be read.
 *
 * A list with the order visible and movable, because `collections-and-reading-lists` makes
 * the order the meaning: "the new order persists", and the next entry offered at the end of
 * one is the next in *this* order rather than the next in a series.
 *
 * Buttons rather than drag: a drag handle in a Compose list is a custom gesture, and two
 * arrows are reachable by a screen reader without one.
 *
 * `library-browsing` also asks for the order to be nameable, overridable and returned to;
 * [ListOrder] holds that rule and [ListOrderChips] is the control.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun ReadingListDetailScreen(
    viewModel: LibraryViewModel,
    id: UUID,
    /**
     * An entry was chosen: that publication's page.
     *
     * A numbered row here is the list saying *this one*, not *carry on where you were* —
     * the reader's position in the list is the count above, and the rows themselves are the
     * shelf. So a row takes the same verb a cover in a collection takes.
     */
    onOpen: (Publication) -> Unit,
    onBack: () -> Unit,
    /** Marks a publication read. The app layer owns the secrets the server may need. */
    onMark: (Publication, Boolean) -> Unit = { _, _ -> },
    /**
     * What a copy onto a server needs from the app layer, which owns the secrets. Null on a
     * screen wired without one, which then does not offer the action at all.
     */
    promoter: ListPromoter? = null,
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val publications by viewModel.publications.collectAsStateWithLifecycle()

    val list = shelves.lists.firstOrNull { it.id == id }
    val entries = list?.entries ?: emptyList()
    val finished = viewModel.finishedPublications()
    val position = list?.position { it in finished } ?: 0

    // How the reader has asked to see the list, for as long as they are looking at it.
    //
    // `library-browsing` gives a chosen order "that session" and no longer, and this is the
    // shortest honest reading of it: leaving the list ends the session, and coming back lands
    // on the order the list carries -- which is the order that means something. Saved rather
    // than merely remembered so a rotation is not a return. Two values rather than one
    // `ListOrder`, because an enum and a boolean are both saveable to a `Bundle` on their own
    // and a data class would need a `Saver` written for it to say the same thing.
    var sort by rememberSaveable { mutableStateOf<LibrarySort?>(null) }
    var ascending by rememberSaveable { mutableStateOf(true) }
    val order = ListOrder(sort = sort, ascending = ascending)

    // What is drawn, and what each row is numbered. The list keeps its own order throughout:
    // `shown` is a new sequence and `numbers` is read off `entries`.
    //
    // Not wrapped in a `remember`: the last-read and progress orders read the view model's
    // progress map, and a snapshot read taken inside a `remember` neither subscribes nor runs
    // again — a list sorted by last read would sit at the order it had when the screen opened
    // and quietly stop agreeing with the ticks beside its own rows. A reading list is tens of
    // entries, so the pass costs nothing worth that.
    //
    // The reader's language, for the reason [LibraryViewModel.rebuild] gives: a reading list
    // sorted by title has to collate the way the shelf does, and the shelf now collates in the
    // chosen language rather than the device's.
    //
    // This one *is* remembered, unlike `shown` above. It reads the settings blob and decodes
    // it, so an unremembered call ran that decode on every recomposition — once per frame while
    // a reader drags a row. Remembering it cannot go stale: changing the language recreates the
    // activity, and the composition this remembers in goes with it.
    val locale = remember { viewModel.readerLocale() }
    val shown = ListOrdering.arrange(
        entries,
        order,
        publications,
        locale = locale,
        progress = viewModel::stateOf,
    )
    val numbers = remember(entries) { ListOrdering.positions(entries) }

    val snackbars = remember { SnackbarHostState() }
    var undo by remember { mutableStateOf<BulkUndo?>(null) }
    BulkUndoEffect(undo, snackbars, viewModel, publications, onMark, promoter) { undo = null }

    var restarting by remember { mutableStateOf<Publication?>(null) }
    // Whether the reader is choosing which cover this list wears. Task 7.13.
    var isChoosingCover by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
        topBar = {
            DetailBar(list?.name.orEmpty(), onBack) {
                // Task 7.13: "unless the user sets a specific one" of a reading list, the
                // way `CollectionDetailScreen` already offers it. A list holding nothing has
                // nothing to offer, so it does not ask -- the same gate the collection's own
                // button keeps.
                if (entries.isNotEmpty()) {
                    IconButton(onClick = { isChoosingCover = true }) {
                        Icon(
                            imageVector = Icons.Filled.GridView,
                            contentDescription = stringResource(R.string.shelves_cover),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
                // The whole list at once. Its entries rather than the publications behind
                // them: an entry whose source dropped the publication is skipped by the
                // action itself rather than left out of what the reader asked for.
                //
                // The list itself goes too: `collections-and-reading-lists` offers to copy a
                // local one onto a server, and the offer belongs where the reader is looking
                // at the list.
                ShelfBulkMenu(
                    viewModel = viewModel,
                    members = entries.toSet(),
                    publications = publications,
                    onMark = onMark,
                    onChange = { undo = it },
                    promoting = list,
                    promoter = promoter,
                )
            }
        },
    ) { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
        ) {
            if (entries.isEmpty()) {
                item {
                    Text(
                        text = stringResource(R.string.shelves_list_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textSecondary,
                    )
                }
            } else {
                item {
                    // One `Column` rather than two siblings: an item's content is a single
                    // slot, and what stacks inside it has to say so.
                    Column(modifier = Modifier.padding(bottom = StoryArcSpace.xs)) {
                        // `collections-and-reading-lists`: a list "shows how many entries are
                        // finished and where the user's position is".
                        Text(
                            text = stringResource(
                                R.string.shelves_list_progress,
                                position,
                                entries.size,
                            ),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textSecondary,
                        )
                        // `collections-and-reading-lists`' bulk download states a count and a
                        // size before it starts; this states the same question the other way,
                        // up front. An entry whose publication is gone is every entry minus
                        // the ones `shown` can still answer for, so the total is `entries.size`
                        // rather than derived from the (possibly shorter) publication list.
                        val onDevice = shown.count { entry ->
                            publications.firstOrNull { it.id == entry }
                                ?.let { isOnDevice(viewModel.location(it)) } == true
                        }
                        ShelfOnDeviceLine(onDevice, entries.size)
                        // `library-browsing`: the curated order is "labelled as such -- not
                        // alphabetical", another field applies for the session, and there is
                        // a one-tap way back. The chip carries the name of the order it is
                        // in, which is what does the labelling.
                        ListOrderChips(
                            order = order,
                            onSortChange = { sort = it },
                            onDirectionChange = { ascending = it },
                            onCurated = { sort = null },
                        )
                    }
                }
                itemsIndexed(shown, key = { _, entry -> entry }) { index, entry ->
                    val publication = publications.firstOrNull { it.id == entry }
                    EntryRow(
                        // The entry's place in the *list*, never its place on screen. Under a
                        // chosen sort that is the more useful of the two, and it is the
                        // visible proof that the curated order is still there underneath.
                        number = numbers[entry] ?: 0,
                        entry = entry,
                        publication = publication,
                        viewModel = viewModel,
                        isFinished = entry in finished,
                        // Moving is offered only in the curated order. `ListOrder` says why
                        // it has to be: these buttons move an entry by the position it
                        // occupies as drawn, and that position written into the curated order
                        // would scramble the thing the reader was promised would not change.
                        canMoveUp = order.allowsReordering && index > 0,
                        canMoveDown = order.allowsReordering && index + 1 < shown.size,
                        isReorderable = order.allowsReordering,
                        onOpen = { publication?.let(onOpen) },
                        onMark = onMark,
                        onRestart = { restarting = it },
                        onUp = { viewModel.moveInList(entry, index - 1, id) },
                        onDown = { viewModel.moveInList(entry, index + 2, id) },
                        onRemove = { viewModel.removeFromList(entry, id) },
                    )
                }
            }
        }
    }

    if (isChoosingCover && list != null) {
        ShelfCoverPicker(
            viewModel = viewModel,
            subject = ShelfCoverSubject.OfList(list),
            onDismiss = { isChoosingCover = false },
        )
    }

    val restart = restarting
    if (restart != null) {
        RestartConfirmation(
            publication = restart,
            viewModel = viewModel,
            onDismiss = { restarting = null },
        )
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun DetailBar(
    title: String,
    onBack: () -> Unit,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
) {
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
        actions = actions,
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EntryRow(
    number: Int,
    entry: String,
    publication: Publication?,
    viewModel: LibraryViewModel,
    isFinished: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    isReorderable: Boolean,
    onOpen: () -> Unit,
    /** Marks a publication read. The app layer owns the secrets the server may need. */
    onMark: (Publication, Boolean) -> Unit,
    /** Opens the confirmation `reading-progress` requires before clearing progress. */
    onRestart: (Publication) -> Unit,
    onUp: () -> Unit,
    onDown: () -> Unit,
    onRemove: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val title = publication?.displayTitle ?: entry
    val isAvailable = publication != null

    // The same menu every other cell offers. Null where [publication] is null: an entry the
    // library holds no publication for has nothing a menu could act on.
    val actions = publication?.let {
        PublicationActionCallbacks(
            onMark = onMark,
            onRestart = onRestart,
            onShowDetails = { onOpen() },
            onRemoveFromShelf = { onRemove() },
        )
    }
    var menuTarget by remember { mutableStateOf<Publication?>(null) }

    // `collections-and-reading-lists`' delta: "each entry shows the publication's own cover
    // beside its position in the list" -- the same fetch `ShelfCover` already makes for the
    // shelf's own artwork. A row's own `remember`/`LaunchedEffect` rather than one dictionary
    // held by the screen, the way `CoverList.kt`'s `ListRow` already fetches its own.
    val density = LocalDensity.current
    val maxPixelSize = remember(density) { with(density) { (POSTER_HEIGHT * 2f / 3f).roundToPx() } }
    var cover by remember(entry) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(entry, publication, publication?.let { viewModel.coverRevision(it) }) {
        cover = publication?.let { viewModel.cover(it, maxPixelSize) }
    }

    val badge = readingListRowBadge(
        isFinished = isFinished,
        percentRead = publication?.let { viewModel.readFraction(it) }
            ?.takeIf { !isFinished }
            ?.let { (it * 100).toInt() },
    )
    val drawnBadge = when (badge) {
        ReadingListRowBadge.Finished -> stringResource(R.string.library_cell_finished)
        is ReadingListRowBadge.PartRead -> stringResource(R.string.library_cell_progress, badge.percent)
        ReadingListRowBadge.None -> null
    }
    val unavailableLabel = stringResource(R.string.shelves_list_unavailable)
    val spoken = when {
        !isAvailable -> unavailableLabel
        drawnBadge != null -> drawnBadge
        else -> stringResource(R.string.library_read_state_unread)
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                enabled = isAvailable,
                onClick = onOpen,
                onLongClick = if (actions != null) { { menuTarget = publication } } else null,
            )
            .defaultMinSize(minHeight = 48.dp)
            // The row's own merged label: its place in the list, its title and its read
            // state in the library's own words -- including "Unread", the one state with
            // nothing drawn for a sighted reader to see either.
            .semantics(mergeDescendants = true) {
                contentDescription = "$number. $title. $spoken"
            },
    ) {
        Text(
            text = "$number",
            style = MaterialTheme.typography.bodySmall,
            color = palette.textTertiary,
        )
        // The library's own cover shape, at a row's height -- `KavitaShelfScreens.kt`'s
        // server row already draws it this way.
        Box(
            modifier = Modifier
                .height(POSTER_HEIGHT)
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(StoryArcRadius.sm))
                .background(palette.surfaceRaised),
        ) {
            cover?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Column(modifier = Modifier.weight(1f).padding(start = StoryArcSpace.xs)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (isAvailable) palette.textPrimary else palette.textSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            // `collections-and-reading-lists`: an entry whose source no longer has the
            // publication "remains in the list, marked unavailable, and does not break the
            // ordering or the next flow" -- said in place of the read state, which an
            // unavailable entry has none of.
            val beneath = if (isAvailable) drawnBadge else unavailableLabel
            beneath?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isAvailable) palette.textSecondary else palette.textTertiary,
                )
            }
        }
        // Absent rather than disabled while a sort is overriding the list. Two greyed arrows
        // on every row would be a control the reader has to work out is unreachable, on the
        // one screen where a narrow window has the least room to spare.
        if (isReorderable) {
            IconButton(onClick = onUp, enabled = canMoveUp) {
                Icon(
                    Icons.Filled.ArrowUpward,
                    contentDescription = stringResource(R.string.shelves_move_up, title),
                    tint = palette.textSecondary,
                )
            }
            IconButton(onClick = onDown, enabled = canMoveDown) {
                Icon(
                    Icons.Filled.ArrowDownward,
                    contentDescription = stringResource(R.string.shelves_move_down, title),
                    tint = palette.textSecondary,
                )
            }
        }
        IconButton(onClick = onRemove) {
            Icon(
                Icons.Filled.Close,
                contentDescription = stringResource(R.string.shelves_remove_entry, title),
                tint = palette.textSecondary,
            )
        }

        if (actions != null) {
            PublicationActionMenuTarget(
                target = menuTarget,
                viewModel = viewModel,
                actions = actions,
                onDismiss = { menuTarget = null },
                onOpen = { onOpen() },
            )
        }
    }
}

/** A list row's own cover, at row height. `KavitaShelfScreens.kt`'s own constant is private
 * to that file, so the local row keeps its own rather than widening it to share one. */
private val POSTER_HEIGHT = 56.dp
