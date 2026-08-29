package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.BulkSelection
import kotlinx.coroutines.launch

/**
 * What can be done to everything the reader has picked.
 *
 * `collections-and-reading-lists` wants a selection added to a collection or a list,
 * downloaded, and marked read. Every one of these is the single-publication path applied to
 * a set: [AddToShelfSheet] is the same sheet a long press opens, the mark is the same mark,
 * and the copy is the same one the app makes when a share goes away.
 *
 * Along the foot of the library, where a thumb is, and where the count stays visible while
 * the reader keeps picking. iOS's `BulkActionBar` offers the same four things.
 */
@Composable
internal fun BulkActionBar(
    viewModel: LibraryViewModel,
    selection: LibrarySelection,
    onSelectionChange: (LibrarySelection) -> Unit,
    /** Opens the add-to sheet over the whole selection. The screen hosts it. */
    onAddToShelf: () -> Unit,
    /**
     * Marks the selection read. The screen does it, because marking also tells the server a
     * publication came from and the app layer is what holds that server's secrets.
     */
    onMarkRead: () -> Unit,
    /** What the action changed, so the screen can offer one undo for the set. */
    onChange: (BulkUndo) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current

    // What the download would actually copy, and what it weighs. Asked when the reader
    // taps, not on every recomposition: it reads the download store off disk.
    var pending by remember { mutableStateOf<Pair<Set<String>, Long>?>(null) }
    var isAllOnDevice by remember { mutableStateOf(false) }

    Surface(color = palette.surfaceRaised, modifier = modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        ) {
            Text(
                text = pluralStringResource(
                    R.plurals.library_selected,
                    selection.count,
                    selection.count,
                ),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textSecondary,
                modifier = Modifier.weight(1f),
            )

            val enabled = selection.ids.isNotEmpty()

            IconButton(onClick = onAddToShelf, enabled = enabled) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.PlaylistAdd,
                    contentDescription = stringResource(R.string.shelves_add_to),
                    tint = palette.accent,
                )
            }

            IconButton(
                enabled = enabled,
                onClick = {
                    val ids = BulkSelection.downloading(selection.ids, viewModel.keptOffline())
                    if (ids.isEmpty()) {
                        isAllOnDevice = true
                    } else {
                        pending = ids to viewModel.bytesOnDisk(ids)
                    }
                },
            ) {
                Icon(
                    imageVector = Icons.Filled.Download,
                    contentDescription = stringResource(R.string.library_bulk_download),
                    tint = palette.accent,
                )
            }

            IconButton(enabled = enabled, onClick = onMarkRead) {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = stringResource(R.string.library_mark_read),
                    tint = palette.accent,
                )
            }

            // The way out. One action: it leaves the mode and drops the picks together,
            // because a reader who has finished picking has finished with both.
            TextButton(onClick = { onSelectionChange(selection.end()) }) {
                Text(stringResource(R.string.library_select_done))
            }
        }
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
                    pluralStringResource(
                        R.plurals.library_bulk_download_title,
                        ids.size,
                        ids.size,
                    ),
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
                        onChange(BulkUndo(BulkUndo.Kind.Kept, viewModel.keepOffline(ids)))
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
