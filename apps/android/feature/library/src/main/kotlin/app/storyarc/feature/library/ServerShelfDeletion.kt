package app.storyarc.feature.library

import android.content.Context
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.persistence.KavitaProgressStore

/**
 * The server shelf a reader has asked to delete and not yet answered for.
 *
 * `collections-and-reading-lists`: a server shelf is "the same kind of object as locally
 * created ones", and [ShelfDeletion] is that promise for a local one -- this is its twin for
 * one the server holds, task 12.6. Deleting is confirmed the same way, with the same two
 * sentences local shelves use: the publications themselves are never at risk, on a server
 * any more than on this device.
 */
internal data class ServerShelfDeletion(
    val id: Int,
    val name: String,
    val isCollection: Boolean,
    val sourceId: String,
    val address: KavitaAddress,
) {
    companion object {
        fun of(shelf: ServerShelf): ServerShelfDeletion =
            ServerShelfDeletion(shelf.id, shelf.title, !shelf.isList, shelf.server.id, shelf.server.address)
    }
}

@Composable
internal fun ServerShelfDeletionDialog(
    deletion: ServerShelfDeletion,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.shelves_delete_title, deletion.name)) },
        text = {
            Text(
                stringResource(
                    if (deletion.isCollection) {
                        R.string.shelves_delete_collection_body
                    } else {
                        R.string.shelves_delete_list_body
                    },
                ),
            )
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.shelves_delete_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shelves_cancel))
            }
        },
    )
}

/** Sends the deletion a reader confirmed, queuing it when the server is not there. */
internal suspend fun ServerShelfDeletion.send(context: Context) {
    KavitaSync.deleteShelf(
        store = KavitaProgressStore.open(context),
        address = address,
        sourceId = sourceId,
        listId = id,
        isCollection = isCollection,
    )
}
