package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.BulkSelection
import app.storyarc.core.model.Publication
import kotlinx.coroutines.launch

/**
 * What can be done with a publication that is not "open it".
 *
 * Where a publication can be put, and whether it has been read.
 *
 * `collections-and-reading-lists`: "a publication may belong to any number of collections".
 * So this offers every one of them rather than a picker that implies a single answer, and
 * says so plainly when there is nowhere to put it yet.
 *
 * Takes a set rather than one publication, because the spec also asks for publications to be
 * "selected in bulk from the library" and a bulk add is this sheet with more than one thing
 * in it. A long press passes the one cover it was opened on; the selection bar passes what
 * the reader picked. There is no second implementation of either.
 *
 * iOS puts the same choice in a context menu, which is where iOS readers look.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun AddToShelfSheet(
    viewModel: LibraryViewModel,
    publications: List<Publication>,
    onDismiss: () -> Unit,
    /** Called with the publications whose read state actually changes, and what it becomes. */
    onMark: ((List<Publication>, Boolean) -> Unit)? = null,
    onAddToServerList: (suspend (Publication, ServerList) -> Boolean)? = null,
    /**
     * What the action changed, for a caller that offers an undo. Null for one publication
     * out of a long press, which has nothing to undo it with.
     */
    onChange: ((BulkUndo) -> Unit)? = null,
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val serverLists by viewModel.serverLists.collectAsStateWithLifecycle()
    val visible by viewModel.visible.collectAsStateWithLifecycle()
    val ids = publications.map { it.id }.toSet()
    val finished = viewModel.finishedPublications()
    // Read, unless every one of them already is -- which for a single cover is the same
    // read/unread toggle it has always been.
    val marksRead = !finished.containsAll(ids)
    val scope = rememberCoroutineScope()

    // Shown when a reader tries to put a publication into a list that cannot hold it.
    var refused by remember { mutableStateOf<String?>(null) }

    fun report(kind: BulkUndo.Kind, changed: Set<String>) {
        if (changed.isNotEmpty()) onChange?.invoke(BulkUndo(kind, changed))
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.xl),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            // `reading-progress`: a reader can mark a publication read "manually", which
            // until now they could only do by turning every page of it.
            if (onMark != null) {
                Row(
                    name = stringResource(
                        if (marksRead) R.string.library_mark_read else R.string.library_mark_unread,
                    ),
                    isMember = false,
                    enabled = true,
                ) {
                    val changing = BulkSelection.marking(ids, marksRead, finished)
                    onMark(publications.filter { it.id in changing }, marksRead)
                    report(BulkUndo.Kind.Read(marksRead), changing)
                    onDismiss()
                }
            }

            Text(
                text = stringResource(R.string.shelves_add_to),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
                modifier = Modifier.padding(bottom = StoryArcSpace.sm),
            )

            if (shelves.collections.isEmpty() && shelves.lists.isEmpty()) {
                Text(
                    text = stringResource(R.string.shelves_collections_none),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                )
            }

            shelves.collections.forEach { collection ->
                val joining = BulkSelection.joining(ids, collection)
                Row(
                    name = collection.name,
                    isMember = joining.isEmpty(),
                    // Every one of them is already in it, so there is nothing a tap changes.
                    enabled = joining.isNotEmpty(),
                ) {
                    report(
                        BulkUndo.Kind.Collection(collection.id),
                        viewModel.addSelectionToCollection(ids, collection.id),
                    )
                    onDismiss()
                }
            }

            shelves.lists.forEach { list ->
                val appending = BulkSelection.appending(ids, list, visible.map { it.id })
                Row(
                    name = list.name,
                    isMember = appending.isEmpty(),
                    enabled = appending.isNotEmpty(),
                ) {
                    report(
                        BulkUndo.Kind.Listing(list.id),
                        viewModel.appendSelectionToList(ids, list.id).toSet(),
                    )
                    onDismiss()
                }
            }

            // A server's own lists, offered like any other. Whether these publications can
            // go in one is the server's rule, not something to hide by leaving the row out:
            // a list a reader cannot see is a list they will look for.
            if (onAddToServerList != null) {
                serverLists.forEach { list ->
                    Row(
                        name = "${list.title} · ${list.server.title}",
                        isMember = false,
                        enabled = true,
                    ) {
                        scope.launch {
                            // Refused once rather than once per publication: a selection of
                            // forty from a folder would otherwise raise forty identical
                            // alerts about the same server.
                            var accepted = 0
                            for (publication in publications) {
                                accepted += if (onAddToServerList(publication, list)) 1 else 0
                            }
                            if (accepted < publications.size) {
                                refused = list.server.title
                            } else {
                                onDismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    refused?.let { server ->
        AlertDialog(
            onDismissRequest = { refused = null },
            title = { Text(stringResource(R.string.shelves_server_only_title)) },
            text = { Text(stringResource(R.string.shelves_server_only_body, server)) },
            confirmButton = {
                TextButton(onClick = {
                    // The offer the spec asks for: a local list can hold anything.
                    val named = publications.firstOrNull()?.displayTitle
                    if (named != null) {
                        viewModel.createList(named)
                        viewModel.appendToList(
                            publications.map { it.id },
                            viewModel.shelves.value.lists.last().id,
                        )
                    }
                    refused = null
                    onDismiss()
                }) {
                    Text(stringResource(R.string.shelves_server_only_local))
                }
            },
            dismissButton = {
                TextButton(onClick = { refused = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

@Composable
private fun Row(name: String, isMember: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = if (isMember) "$name ✓" else name,
        style = MaterialTheme.typography.bodyLarge,
        color = if (enabled) palette.textPrimary else palette.textTertiary,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onTap)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.sm),
    )
}
