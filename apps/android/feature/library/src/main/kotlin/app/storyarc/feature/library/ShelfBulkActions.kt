package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.BulkSelection
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Acting on a whole collection or reading list at once.
 *
 * `collections-and-reading-lists`' last requirement: a reader downloads "an entire collection
 * or reading list" and is told "the item count and total size before starting", or marks one
 * read, "and the action is undoable for 10 seconds".
 *
 * One menu rather than two copies of it, because a collection and a list differ in how they
 * are *shown* -- a grid and a numbered run -- and not at all in what can be done to
 * everything inside them. The actions are the ones the library's selection bar uses, handed
 * the membership instead of a selection. iOS's `ShelfBulkActions` is the same modifier.
 */
@Composable
internal fun ShelfBulkMenu(
    viewModel: LibraryViewModel,
    /** Everything the shelf holds. An entry whose publication has gone is simply not in it. */
    members: Set<String>,
    publications: List<Publication>,
    onMark: (Publication, Boolean) -> Unit,
    onChange: (BulkUndo) -> Unit,
    /**
     * The list this shelf is, when it is a local reading list that could go on a server.
     * Null for a collection, and for a list a server already holds.
     */
    promoting: ReadingList? = null,
    /** What a copy needs from the app layer. Null on a screen that cannot offer one. */
    promoter: ListPromoter? = null,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listServers by viewModel.listServers.collectAsStateWithLifecycle()

    var isOpen by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<Pair<Set<String>, Long>?>(null) }
    var isAllOnDevice by remember { mutableStateOf(false) }
    var isPromoting by remember { mutableStateOf(false) }

    IconButton(onClick = { isOpen = true }, enabled = members.isNotEmpty()) {
        Icon(
            imageVector = Icons.Filled.MoreVert,
            contentDescription = stringResource(R.string.shelves_bulk),
            tint = palette.accent,
        )
    }

    DropdownMenu(expanded = isOpen, onDismissRequest = { isOpen = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_mark_read)) },
            onClick = {
                isOpen = false
                val changing =
                    BulkSelection.marking(members, true, viewModel.finishedPublications())
                publications.filter { it.id in changing }.forEach { onMark(it, true) }
                if (changing.isNotEmpty()) onChange(BulkUndo(BulkUndo.Kind.Read(true), changing))
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_bulk_download)) },
            onClick = {
                isOpen = false
                val ids = BulkSelection.downloading(members, viewModel.keptOffline())
                if (ids.isEmpty()) isAllOnDevice = true else pending = ids to viewModel.bytesOnDisk(ids)
            },
        )
        // `collections-and-reading-lists` offers to copy a local list to a server. Disabled
        // with the reason under it rather than hidden: a reader who cannot find the action
        // does not learn that their server is unreachable, they learn that the app cannot
        // do it.
        if (promoting != null && promoter != null && promoting.origin == ShelfOrigin.Local) {
            DropdownMenuItem(
                enabled = listServers.isNotEmpty(),
                text = {
                    Column {
                        Text(stringResource(R.string.shelves_promote))
                        if (listServers.isEmpty()) {
                            Text(
                                text = stringResource(R.string.shelves_promote_unavailable),
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.textSecondary,
                            )
                        }
                    }
                },
                onClick = {
                    isOpen = false
                    isPromoting = true
                },
            )
        }
    }

    if (isPromoting && promoting != null && promoter != null) {
        PromoteListSheet(
            viewModel = viewModel,
            list = promoting,
            promoter = promoter,
            onDismiss = { isPromoting = false },
            onCopied = onChange,
        )
    }

    if (isAllOnDevice) {
        AlertDialog(
            onDismissRequest = { isAllOnDevice = false },
            text = { Text(stringResource(R.string.library_bulk_download_none)) },
            confirmButton = {
                TextButton(onClick = { isAllOnDevice = false }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }

    // `offline-downloads`: the app "states the item count and total size and asks for
    // confirmation before queueing them". Both, before anything is copied.
    pending?.let { (ids, bytes) ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = {
                Text(
                    pluralStringResource(R.plurals.library_bulk_download_title, ids.size, ids.size),
                )
            },
            text = {
                Text(
                    stringResource(
                        R.string.library_bulk_download_size,
                        android.text.format.Formatter.formatFileSize(context, bytes),
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    pending = null
                    scope.launch {
                        val kept = viewModel.keepOffline(ids)
                        if (kept.isNotEmpty()) onChange(BulkUndo(BulkUndo.Kind.Kept, kept))
                    }
                }) {
                    Text(stringResource(R.string.library_bulk_download))
                }
            },
            dismissButton = {
                TextButton(onClick = { pending = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

/**
 * The undo a bulk action leaves behind.
 *
 * `collections-and-reading-lists`: the action "is undoable for 10 seconds". Ten, and then
 * gone -- an offer that outlived its window would put back a change the reader had long
 * since accepted. One effect shared by the library and the two shelf screens, so the window
 * cannot come to mean two different lengths.
 */
@Composable
internal fun BulkUndoEffect(
    undo: BulkUndo?,
    snackbars: SnackbarHostState,
    viewModel: LibraryViewModel?,
    publications: List<Publication>,
    onMark: (Publication, Boolean) -> Unit,
    /**
     * Takes a copied list back off its server. Null on a screen that cannot copy one there,
     * which is every screen but a local reading list's.
     */
    promoter: ListPromoter? = null,
    onSettle: () -> Unit,
) {
    val message = undo?.let {
        pluralStringResource(R.plurals.library_bulk_changed, it.ids.size, it.ids.size)
    }
    val undoLabel = stringResource(R.string.downloads_undo)

    LaunchedEffect(undo?.kind, undo?.ids) {
        val record = undo ?: return@LaunchedEffect
        val text = message ?: return@LaunchedEffect
        val answer = withTimeoutOrNull(UNDO_WINDOW_MILLIS) {
            snackbars.showSnackbar(
                message = text,
                actionLabel = undoLabel,
                duration = SnackbarDuration.Indefinite,
            )
        }
        if (answer == SnackbarResult.ActionPerformed && viewModel != null) {
            when (val kind = record.kind) {
                is BulkUndo.Kind.Collection -> viewModel.removeFromCollection(record.ids, kind.id)
                is BulkUndo.Kind.Listing ->
                    record.ids.forEach { viewModel.removeFromList(it, kind.id) }

                is BulkUndo.Kind.Read -> publications
                    .filter { it.id in record.ids }
                    .forEach { onMark(it, !kind.wasRead) }

                BulkUndo.Kind.Kept -> viewModel.forgetKept(record.ids)

                is BulkUndo.Kind.Promoted -> promoter?.withdraw(kind.sourceId, kind.listId)
            }
        }
        onSettle()
    }
}

/** Ten seconds, which is what `collections-and-reading-lists` promises. */
private const val UNDO_WINDOW_MILLIS = 10_000L
