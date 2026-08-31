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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CheckCircle
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
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
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
                            tint = palette.accent,
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
                CoverGrid(
                    publications = members,
                    viewModel = viewModel,
                    continueReading = emptyList(),
                    onOpen = onOpen,
                )
            }
        }
    }

    if (isChoosingCover && collection != null) {
        ShelfCoverPicker(
            viewModel = viewModel,
            collection = collection,
            onDismiss = { isChoosingCover = false },
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

    val snackbars = remember { SnackbarHostState() }
    var undo by remember { mutableStateOf<BulkUndo?>(null) }
    BulkUndoEffect(undo, snackbars, viewModel, publications, onMark, promoter) { undo = null }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
        topBar = {
            DetailBar(list?.name.orEmpty(), onBack) {
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
                        modifier = Modifier.padding(bottom = StoryArcSpace.sm),
                    )
                }
                itemsIndexed(entries, key = { _, entry -> entry }) { index, entry ->
                    val publication = publications.firstOrNull { it.id == entry }
                    EntryRow(
                        number = index + 1,
                        title = publication?.displayTitle ?: entry,
                        isAvailable = publication != null,
                        isFinished = entry in finished,
                        canMoveUp = index > 0,
                        canMoveDown = index + 1 < entries.size,
                        onOpen = { publication?.let(onOpen) },
                        onUp = { viewModel.moveInList(entry, index - 1, id) },
                        onDown = { viewModel.moveInList(entry, index + 2, id) },
                        onRemove = { viewModel.removeFromList(entry, id) },
                    )
                }
            }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun DetailBar(
    title: String,
    onBack: () -> Unit,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
) {
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
        actions = actions,
    )
}

@Composable
private fun EntryRow(
    number: Int,
    title: String,
    isAvailable: Boolean,
    isFinished: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onOpen: () -> Unit,
    onUp: () -> Unit,
    onDown: () -> Unit,
    onRemove: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = isAvailable, onClick = onOpen)
            .defaultMinSize(minHeight = 48.dp),
    ) {
        Text(
            text = "$number",
            style = MaterialTheme.typography.bodySmall,
            color = palette.textTertiary,
        )
        Column(modifier = Modifier.weight(1f).padding(start = StoryArcSpace.xs)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (isAvailable) palette.textPrimary else palette.textSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (!isAvailable) {
                // `collections-and-reading-lists`: an entry whose source no longer has the
                // publication "remains in the list, marked unavailable, and does not break
                // the ordering or the next flow". Removing it would renumber everything
                // after it.
                Text(
                    text = stringResource(R.string.shelves_list_unavailable),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textTertiary,
                )
            }
        }
        if (isFinished) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = palette.accent,
            )
        }
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
        IconButton(onClick = onRemove) {
            Icon(
                Icons.Filled.Close,
                contentDescription = stringResource(R.string.shelves_remove_entry, title),
                tint = palette.textSecondary,
            )
        }
    }
}
