package app.storyarc.feature.library

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.Shelves
import java.util.UUID

/**
 * A shelf the reader has asked to delete, and has not answered for yet.
 *
 * `collections-and-reading-lists`: when a reader deletes a collection "the app confirms and
 * states plainly that the publications themselves are not deleted". A confirmation needs
 * something to hold between the question and the answer, and this is it -- the name, so the
 * question can say which shelf, and the kind, so the sentence can name what actually goes.
 *
 * Confirmation rather than the ten-second undo the bulk actions use. The spec names the two
 * halves of this scenario and both are the dialogue's: a reader deleting a shelf is afraid of
 * losing the books on it, and a snackbar that appears *after* the shelf has gone answers that
 * fear too late to be reassurance. The undo is right for an action whose result is visible and
 * reversible; this one's result is an absence.
 *
 * The value is the whole safety property. While one of these exists nothing has been written,
 * and [apply] -- the only thing that writes -- is reached from the confirming button alone.
 *
 * iOS's `ShelfDeletion` is the same type, asserted case for case.
 */
internal data class ShelfDeletion(
    val id: UUID,
    val name: String,
    val kind: Kind,
) {
    /**
     * Which of the two shelves this is.
     *
     * Not a flag on one type, for the reason the spec gives for keeping a collection and a
     * reading list apart, and because the sentence the reader reads differs by exactly this
     * word: what is going is *the collection* or *the reading list*, never "the shelf".
     */
    enum class Kind { COLLECTION, LIST }

    /**
     * Carries the deletion out. Nothing that happened before this call changed anything.
     *
     * It takes [Shelves] and answers [Shelves], and a publication is neither. That is the
     * sentence the dialogue makes to the reader, held up by the types: a shelf is a set of
     * identities, and deleting one can only ever drop the set.
     */
    fun apply(shelves: Shelves): Shelves = when (kind) {
        Kind.COLLECTION -> shelves.deletingCollection(id)
        Kind.LIST -> shelves.deletingList(id)
    }

    companion object {
        fun of(collection: PublicationCollection): ShelfDeletion =
            ShelfDeletion(collection.id, collection.name, Kind.COLLECTION)

        fun of(list: ReadingList): ShelfDeletion =
            ShelfDeletion(list.id, list.name, Kind.LIST)
    }
}

/**
 * The question a shelf is deleted through.
 *
 * Both halves the spec asks for, and the second is the one that earns its place: what a reader
 * fears when they delete a shelf is losing the books on it, so the message says they keep them
 * and says nothing else. iOS's `shelfDeletionConfirmation` is the same dialogue.
 */
@Composable
internal fun ShelfDeletionDialog(
    deletion: ShelfDeletion,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.shelves_delete_title, deletion.name)) },
        text = {
            Text(
                stringResource(
                    when (deletion.kind) {
                        ShelfDeletion.Kind.COLLECTION -> R.string.shelves_delete_collection_body
                        ShelfDeletion.Kind.LIST -> R.string.shelves_delete_list_body
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
