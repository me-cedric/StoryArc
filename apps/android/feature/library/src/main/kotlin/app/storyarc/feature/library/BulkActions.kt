package app.storyarc.feature.library

import java.util.UUID

/**
 * What the reader has picked, and whether they are picking at all.
 *
 * `collections-and-reading-lists` wants publications "selected in bulk from the library".
 * A mode rather than a checkbox on every cover for ever: the library is looked at far more
 * often than it is edited, and a grid wearing forty checkboxes is a filing cabinet.
 *
 * iOS's `LibrarySelection` is the same three questions.
 */
data class LibrarySelection(
    val ids: Set<String> = emptySet(),
    /** Whether a tap picks rather than opens. */
    val isActive: Boolean = false,
) {
    val count: Int get() = ids.size

    fun begin(): LibrarySelection = LibrarySelection(emptySet(), isActive = true)

    /**
     * Leaves the mode and forgets what was picked.
     *
     * The clear way out the requirement asks for, and one action rather than two: a reader
     * who leaves selection mode has finished selecting, and asking them to also empty the
     * set would leave the library holding a decision they had already abandoned.
     */
    fun end(): LibrarySelection = LibrarySelection()

    fun toggle(id: String): LibrarySelection =
        copy(ids = if (id in ids) ids - id else ids + id)

    operator fun contains(id: String): Boolean = id in ids
}

/**
 * What a bulk action did, so one action can put it back.
 *
 * `collections-and-reading-lists`: a bulk mark-read "is undoable for 10 seconds". One undo
 * for the set, not one per publication -- a reader who marked forty issues read by mistake
 * is not going to tap Undo forty times, and the tenth second would arrive first.
 *
 * [ids] is what actually moved. Deliberately not the selection: an undo that put back what
 * was never taken would unread a publication the reader finished weeks ago.
 */
data class BulkUndo(val kind: Kind, val ids: Set<String>) {
    sealed interface Kind {
        data class Collection(val id: UUID) : Kind
        data class Listing(val id: UUID) : Kind
        data class Read(val wasRead: Boolean) : Kind
        data object Kept : Kind
    }
}
