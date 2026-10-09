package app.storyarc.feature.library

import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.Publication
import java.util.UUID
import app.storyarc.core.model.BulkSelection
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import kotlinx.coroutines.flow.update

// The reader's collections and reading lists, and what to offer after a publication is finished.
//
// Moved out of `LibraryViewModel.kt` unchanged, as extensions on the view model, so that
// file stays under the 800-line cap. The state these read stays on the class.

fun LibraryViewModel.createCollection(name: String) {
    if (name.isBlank()) return
    _shelves.update { it.adding(PublicationCollection(name = name.trim())) }
    shelvesStore?.save(_shelves.value)
}

fun LibraryViewModel.createList(name: String) {
    if (name.isBlank()) return
    _shelves.update { it.adding(ReadingList(name = name.trim())) }
    shelvesStore?.save(_shelves.value)
}

fun LibraryViewModel.addToCollection(members: Set<String>, id: UUID) {
    _shelves.update { it.adding(members, id) }
    shelvesStore?.save(_shelves.value)
}

fun LibraryViewModel.appendToList(entries: List<String>, id: UUID) {
    _shelves.update { it.appending(entries, id) }
    shelvesStore?.save(_shelves.value)
}

fun LibraryViewModel.removeFromList(entry: String, id: UUID) {
    _shelves.update { it.removing(entry, id) }
    shelvesStore?.save(_shelves.value)
}

fun LibraryViewModel.moveInList(entry: String, destination: Int, id: UUID) {
    _shelves.update { it.moving(entry, destination, id) }
    shelvesStore?.save(_shelves.value)
}

fun LibraryViewModel.removeFromCollection(members: Set<String>, id: UUID) {
    _shelves.update { it.removing(members, id) }
    shelvesStore?.save(_shelves.value)
}

// Bulk actions: the single-publication paths, applied to a set. Each answers with what
// it changed rather than with nothing, because the undo is built from the change --
// [BulkSelection] works out what that is, and these carry it out.

/** Adds a whole selection to a collection. */
fun LibraryViewModel.addSelectionToCollection(selection: Set<String>, id: UUID): Set<String> {
    val collection = _shelves.value.collections.firstOrNull { it.id == id } ?: return emptySet()
    val joining = BulkSelection.joining(selection, collection)
    if (joining.isEmpty()) return emptySet()
    addToCollection(joining, id)
    return joining
}

/** Appends a whole selection to a reading list, in the order the library is showing it. */
fun LibraryViewModel.appendSelectionToList(selection: Set<String>, id: UUID): List<String> {
    val list = _shelves.value.lists.firstOrNull { it.id == id } ?: return emptyList()
    val entries = BulkSelection.appending(selection, list, _visible.value.map { it.id })
    if (entries.isEmpty()) return emptyList()
    appendToList(entries, id)
    return entries
}

/**
 * Deletes a shelf the reader has confirmed, and not one they have not.
 *
 * The only way a shelf leaves the app, and it takes a [ShelfDeletion] -- which can only be
 * answered by the dialogue that presents it. The two calls this replaced took a bare
 * identity, so a caller could delete a hand-built collection without asking, and one did.
 * `collections-and-reading-lists` requires the confirmation, and the signature is what
 * makes it required rather than remembered.
 */
internal fun LibraryViewModel.delete(deletion: ShelfDeletion) {
    _shelves.update { deletion.apply(it) }
    shelvesStore?.save(_shelves.value)
}

/**
 * Gives a collection a cover of its own, or hands it back to the composite with `null`.
 *
 * `collections-and-reading-lists` makes the composite what a collection wears "unless the
 * user sets a specific one". [Shelves.settingCover] has always been able to store the
 * choice; this is the first thing that asks it to.
 */
fun LibraryViewModel.setCollectionCover(member: String?, id: UUID) {
    _shelves.update { it.settingCover(member, id) }
    shelvesStore?.save(_shelves.value)
}

/**
 * What to offer when a publication is finished.
 *
 * A reading list wins over a series. `collections-and-reading-lists`: when a reader
 * finishes an entry in a list, "the next entry in list order is offered, regardless of
 * series or source" -- a crossover read in publication order is exactly a case where the
 * series' own next issue is the wrong answer.
 *
 * The first list containing it decides, when a publication is in several. Any rule here
 * is arbitrary; this one is at least the reader's own order, since the lists are in the
 * order they made them.
 *
 * Falls back to the series, which is what `comic-reader` asks for and what a reader who
 * keeps no lists will always get.
 */
fun LibraryViewModel.next(after: Publication): Publication? {
    val known = _publications.value
    for (list in _shelves.value.lists) {
        if (after.id !in list.entries) continue
        // An entry whose publication is gone does not stop the flow: walk forward
        // past every unavailable entry before trying the next list or the series.
        var cursor = after.id
        while (true) {
            cursor = list.next(cursor) ?: break
            known.firstOrNull { it.id == cursor }?.let { return it }
        }
    }
    return LibraryIndex.next(after, known)
}

/**
 * What the reader came from, for `comic-reader`'s previous-chapter action.
 *
 * The mirror of [next] and resolved the same way, list before series: a reader who
 * arranged a crossover expects to walk back through their own order, not through the
 * issue numbers it cuts across.
 */
fun LibraryViewModel.previous(before: Publication): Publication? {
    val known = _publications.value
    for (list in _shelves.value.lists) {
        if (before.id !in list.entries) continue
        var cursor = before.id
        while (true) {
            cursor = list.previous(cursor) ?: break
            known.firstOrNull { it.id == cursor }?.let { return it }
        }
    }
    return LibraryIndex.previous(before, known)
}
