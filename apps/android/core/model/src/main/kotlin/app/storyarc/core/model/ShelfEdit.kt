package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * Which server-backed shelf something belongs to.
 *
 * A server, one of its shelves, and which kind of shelf that is. None of the three identifies
 * a shelf on its own: two Kavita servers number their reading lists from one, and one Kavita
 * server numbers its collections and its reading lists from one apiece -- so without the kind,
 * asking for collection 7's members answers with reading list 7's. Seen on a simulator on
 * 2026-10-05: a pinned *Staff picks* drew *Start here*'s three covers, under its own name.
 *
 * The kind is defaulted, and that default is also what a record written before the field
 * existed decodes as: every shelf this type named then was a reading list, because nothing had
 * ever reconciled a collection.
 */
@Serializable
data class ShelfKey(
    val sourceId: String,
    val shelfId: Int,
    val kind: RememberedShelfKind = RememberedShelfKind.READING_LIST,
) {
    /** What a shelf is called in an identifier two kinds would otherwise collide in. */
    val token: String get() = "$sourceId/${kind.word}:$shelfId"
}

/**
 * One edit a reader made to a server-backed reading list that the server has not seen.
 *
 * `collections-and-reading-lists`: an edit made "while the server is unreachable" is
 * "applied locally, marked pending, and pushed on reconnection". All three need the edit to
 * outlive the moment it was made -- the reader who edits on a train has closed the app long
 * before the server is back -- so this is a value, written down, not a task in flight.
 */
@Serializable
data class ShelfEdit(
    val shelf: ShelfKey,
    /**
     * The entry it adds, named the way the server names its own entries, so a pull can tell
     * whether the server has it yet without a second lookup.
     */
    val entry: String,
    /**
     * What to show while it is pending. The server cannot be asked for a title it does not
     * hold yet, and a row reading "pending" with no name is a row about nothing.
     */
    val title: String,
    val madeAt: Long,
) {
    /**
     * What makes two queued edits the same edit. Adding the same entry to the same list
     * twice is one pending edit, not two.
     */
    val id: String get() = "${shelf.token}/$entry"
}

/**
 * One row of a reading list as the reader sees it.
 *
 * Pending or not, because `collections-and-reading-lists` requires "the pending state is
 * visible on the list" -- visible on the list itself, not only in a banner above it.
 */
data class ShelfEntry(val id: String, val title: String, val isPending: Boolean)

/**
 * What one server-backed shelf held, the last time it answered.
 *
 * Kept so a later answer can be compared against it. Without it "the server changed" is
 * unanswerable, and every refresh is either a conflict or none of them.
 */
@Serializable
data class ShelfSnapshot(val shelf: ShelfKey, val entries: List<String>)

/**
 * A conflict that has happened and has not yet been said out loud.
 *
 * `collections-and-reading-lists`: on a conflict "the user is told once what changed".
 * Once is the hard part, and it is why this is written down rather than raised: a notice
 * that lived in a view model would come back on every refresh, and one that lived nowhere
 * would be lost to the launch that follows the conflict.
 */
@Serializable
data class ShelfConflictNotice(
    val shelf: ShelfKey,
    /** What the list is called, so the sentence names it. */
    val shelfName: String,
    /**
     * The titles that were dropped, so the sentence says what changed rather than that
     * something did. Empty for [isOrder], which has no entries to name -- only an order.
     */
    val discarded: List<String> = emptyList(),
    val at: Long,
    /**
     * Whether this is task 7.4's conflict: an order the reader gave the list, dropped
     * because the server's own order had already moved. [discarded] names nothing for one
     * of these, so the sentence it reads from is its own.
     */
    val isOrder: Boolean = false,
) {
    val id: String get() = "${shelf.token}/$at"
}

/**
 * Everything owed to a server, everything last seen from one, and everything still to say.
 *
 * One value rather than three stores, for the reason [Shelves] is one: they are written
 * together in a single reconciliation, and a store that wrote them apart would let an edit
 * outlive the baseline that justifies pushing it.
 *
 * iOS's `ShelfEditQueue` holds the same three lists and the same operations.
 */
@Serializable
data class ShelfEditQueue(
    val edits: List<ShelfEdit> = emptyList(),
    val baselines: List<ShelfSnapshot> = emptyList(),
    val notices: List<ShelfConflictNotice> = emptyList(),
) {
    /** Records an edit, replacing any earlier one for the same entry on the same list. */
    fun queueing(edit: ShelfEdit): ShelfEditQueue =
        copy(edits = edits.filterNot { it.id == edit.id } + edit)

    /** Forgets edits the server no longer needs -- delivered, or discarded by a conflict. */
    fun dropping(done: List<ShelfEdit>): ShelfEditQueue {
        val gone = done.map { it.id }.toSet()
        return copy(edits = edits.filterNot { it.id in gone })
    }

    /** Writes down what a shelf held when it last answered. */
    fun recording(snapshot: ShelfSnapshot): ShelfEditQueue =
        copy(baselines = baselines.filterNot { it.shelf == snapshot.shelf } + snapshot)

    /** What a shelf held when it last answered, or null for one never seen from this device. */
    fun baseline(shelf: ShelfKey): List<String>? =
        baselines.firstOrNull { it.shelf == shelf }?.entries

    /** The edits still owed for one shelf, oldest first. */
    fun pending(shelf: ShelfKey): List<ShelfEdit> =
        edits.filter { it.shelf == shelf }.sortedBy { it.madeAt }

    /** Keeps a conflict until somebody has said it. */
    fun noting(notice: ShelfConflictNotice): ShelfEditQueue = copy(notices = notices + notice)

    /** Drops a notice that has been shown. This is the "once". */
    fun acknowledging(id: String): ShelfEditQueue =
        copy(notices = notices.filterNot { it.id == id })

    /** The oldest thing still to tell the reader, if there is one. */
    val nextNotice: ShelfConflictNotice? get() = notices.minByOrNull { it.at }

    /** Forgets everything one source defined, for when the source itself is removed. */
    fun removingAll(sourceId: String): ShelfEditQueue = ShelfEditQueue(
        edits = edits.filterNot { it.shelf.sourceId == sourceId },
        baselines = baselines.filterNot { it.shelf.sourceId == sourceId },
        notices = notices.filterNot { it.shelf.sourceId == sourceId },
    )
}
