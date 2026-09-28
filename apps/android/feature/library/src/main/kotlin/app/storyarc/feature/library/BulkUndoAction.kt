package app.storyarc.feature.library

import app.storyarc.core.model.Publication

/**
 * Putting a bulk action back.
 *
 * `collections-and-reading-lists`: marking a collection or a list read "is undoable for 10
 * seconds", and so is the copy of a local list onto a server. The ten seconds are the
 * snackbar's; what the reader gets back when they take the offer is this.
 *
 * Beside the snackbar rather than inside it, because a `LaunchedEffect` cannot be asked to
 * run one branch and report what it did. iOS's `LibraryModel.undo` is the same five branches.
 *
 * Only what the action changed is put back. [BulkUndo.ids] is the change, never the
 * selection: a publication the reader finished weeks ago was not marked by this action, and
 * unreading it would be the undo inventing a change of its own.
 */
suspend fun BulkUndo.reverse(
    viewModel: LibraryViewModel,
    publications: List<Publication>,
    onMark: (Publication, Boolean) -> Unit,
    promoter: ListPromoter?,
) {
    when (val undoing = kind) {
        is BulkUndo.Kind.Collection -> viewModel.removeFromCollection(ids, undoing.id)

        is BulkUndo.Kind.Listing -> ids.forEach { viewModel.removeFromList(it, undoing.id) }

        is BulkUndo.Kind.Read -> publications
            .filter { it.id in ids }
            .forEach { onMark(it, !undoing.wasRead) }

        BulkUndo.Kind.Kept -> viewModel.forgetKept(ids)

        is BulkUndo.Kind.Promoted -> promoter?.withdraw(undoing.sourceId, undoing.listId)
    }
}
