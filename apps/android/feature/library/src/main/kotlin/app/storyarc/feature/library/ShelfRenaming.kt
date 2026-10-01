package app.storyarc.feature.library

import java.util.UUID
import kotlinx.coroutines.flow.update

/**
 * Giving a local shelf a new name.
 *
 * `collections-and-reading-lists` lists create, rename and delete as one requirement for a
 * collection or a reading list. `Shelves.renamingCollection` and `Shelves.renamingList` have
 * done the renaming since the day the model was written; nothing on either screen reached
 * them, so the clause was built and unreachable. `ShelfRenameDialog` is the control; this is
 * the model call it makes, split into its own file because [LibraryViewModel] is already at
 * the line cap `scripts/line-cap.mjs` records for it.
 */
fun LibraryViewModel.renameCollection(id: UUID, name: String) {
    _shelves.update { it.renamingCollection(id, name) }
    shelvesStore?.save(_shelves.value)
}

/** The reading-list twin of [renameCollection]. */
fun LibraryViewModel.renameList(id: UUID, name: String) {
    _shelves.update { it.renamingList(id, name) }
    shelvesStore?.save(_shelves.value)
}
