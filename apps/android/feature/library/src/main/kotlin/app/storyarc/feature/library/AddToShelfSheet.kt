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
 * iOS puts the same choice in a context menu, which is where iOS readers look.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun AddToShelfSheet(
    viewModel: LibraryViewModel,
    publication: Publication,
    onDismiss: () -> Unit,
    onMark: ((Boolean) -> Unit)? = null,
    onAddToServerList: (suspend (ServerList) -> Boolean)? = null,
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val serverLists by viewModel.serverLists.collectAsStateWithLifecycle()
    val already = shelves.collectionsContaining(publication.id).map { it.id }.toSet()
    val isRead = publication.id in viewModel.finishedPublications()
    val scope = rememberCoroutineScope()

    // Shown when a reader tries to put a publication into a list that cannot hold it.
    var refused by remember { mutableStateOf<String?>(null) }

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
                        if (isRead) R.string.library_mark_unread else R.string.library_mark_read,
                    ),
                    isMember = false,
                    enabled = true,
                ) {
                    onMark(!isRead)
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
                val contains = collection.id in already
                Row(
                    name = collection.name,
                    isMember = contains,
                    enabled = !contains,
                ) {
                    viewModel.addToCollection(setOf(publication.id), collection.id)
                    onDismiss()
                }
            }

            shelves.lists.forEach { list ->
                val contains = publication.id in list.entries
                Row(
                    name = list.name,
                    isMember = contains,
                    enabled = !contains,
                ) {
                    viewModel.appendToList(listOf(publication.id), list.id)
                    onDismiss()
                }
            }

            // A server's own lists, offered like any other. Whether this publication can go
            // in one is the server's rule, not something to hide by leaving the row out: a
            // list a reader cannot see is a list they will look for.
            if (onAddToServerList != null) {
                serverLists.forEach { list ->
                    Row(
                        name = "${list.title} · ${list.server.title}",
                        isMember = false,
                        enabled = true,
                    ) {
                        scope.launch {
                            if (onAddToServerList(list)) {
                                onDismiss()
                            } else {
                                refused = list.server.title
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
                    viewModel.createList(publication.displayTitle)
                    viewModel.appendToList(
                        listOf(publication.id),
                        viewModel.shelves.value.lists.last().id,
                    )
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
