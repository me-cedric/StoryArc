package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaClient

/**
 * A shelf the reader is making, and the places it could be kept.
 *
 * `collections-and-reading-lists`: a new shelf "is stored locally by default, or on a server
 * if the user chooses one that supports collections", and "the storage location is stated at
 * creation, not discovered later". Both halves need the choice to exist before the shelf
 * does, which is what this holds -- the kind, and the servers that could take it.
 *
 * Only a server that has just answered when asked for shelves of this kind is offered. That
 * is the same rule the copy-onto-a-server offer already follows: reachable and able to hold
 * one, which an empty answer cannot tell apart from no answer.
 *
 * iOS's `ShelfDraft` offers the same destinations in the same order.
 */
data class ShelfDraft(val isList: Boolean, val servers: List<KavitaPage>)

/** Making a shelf somewhere other than this device. */
object ShelfCreation {

    /**
     * Makes the shelf on the server, and answers with it.
     *
     * Null when the server refused. The caller says so rather than pretending: a shelf the
     * reader was told is kept on a server, and is not, is worse than an error they can act
     * on. Nothing is written locally either -- the alternative would be a shelf whose stated
     * home is a lie.
     */
    suspend fun make(isList: Boolean, title: String, page: KavitaPage): ServerShelf? {
        val client = KavitaClient(page.address)
        return if (isList) {
            runCatching { client.createList(title) }.getOrNull()
                ?.let { ServerShelf(page, it.id, it.title, isList = true) }
        } else {
            runCatching { client.createCollection(title) }.getOrNull()
                ?.let { ServerShelf(page, it.id, it.title, isList = false) }
        }
    }
}

/**
 * The question a shelf is made through.
 *
 * One button per destination rather than a picker, because the destinations are a short list
 * and a button already says what it will do. The device is the confirming button and is the
 * default the spec names; a server follows only when it has just answered.
 *
 * The sentence states where the shelf will be kept before it exists, which is the scenario's
 * second half -- "not discovered later".
 */
@Composable
internal fun ShelfCreationDialog(
    draft: ShelfDraft,
    name: String,
    onName: (String) -> Unit,
    onDevice: () -> Unit,
    onServer: (KavitaPage) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                stringResource(
                    if (draft.isList) R.string.shelves_new_list else R.string.shelves_new_collection,
                ),
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                // One location means saying which it is; more than one means saying that the
                // choice is being made now. Either way the reader is told before, not after.
                Text(
                    stringResource(
                        if (draft.servers.isEmpty()) {
                            R.string.shelves_new_stored_locally
                        } else {
                            R.string.shelves_new_choose_where
                        },
                    ),
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = onName,
                    label = { Text(stringResource(R.string.shelves_new_field)) },
                    singleLine = true,
                )
                for (page in draft.servers) {
                    TextButton(onClick = { onServer(page) }) { Text(page.title) }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDevice) {
                Text(
                    stringResource(
                        if (draft.servers.isEmpty()) {
                            R.string.shelves_create
                        } else {
                            R.string.shelves_new_here
                        },
                    ),
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shelves_cancel))
            }
        },
    )
}
