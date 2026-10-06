package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.RememberedShelfKind
import app.storyarc.core.model.ShelfConflictNotice
import app.storyarc.core.model.ShelfEdit
import app.storyarc.core.model.ShelfEntry
import app.storyarc.core.model.ShelfKey
import app.storyarc.core.model.ShelfPull
import app.storyarc.core.model.ShelfSnapshot
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ShelfEditStore

/**
 * Keeping a server-backed shelf and the edits owed to it in step.
 *
 * `collections-and-reading-lists` asks for two things that are one round of work: an edit
 * made while the server was away is "pushed on reconnection", and an edit the server has
 * overtaken loses to it with the reader "told once what changed". Both need the server's
 * current version of the list, so both happen the moment it hands one over.
 *
 * The decisions are not here. [app.storyarc.core.model.ShelfMerge] holds the table, where a
 * test can reach it without a server. This is the part only a server can do: asking, sending,
 * and writing the answer down. iOS's `ShelfSync` does the same three in the same order.
 */
object ShelfSync {

    /** One shelf, as the server currently has it. */
    private data class Fetched(val shelf: ServerShelf, val entries: List<String>)

    /**
     * Reconciles every server shelf that will answer.
     *
     * A shelf that does not answer is simply absent from what is merged, which leaves its
     * edits queued and says nothing about them -- that is the unreachable server, and
     * `sources` is explicit that it is a normal state rather than a failure.
     *
     * **A collection is asked as well as a reading list, and only for its membership.** It
     * carries no pending edit -- nothing offers one -- so the merge finds nothing to push and
     * nothing to drop for it, and the whole of its round is the record it leaves behind. That
     * record is what `home-screen`'s *Pinned shelves* then draws a pinned collection from
     * without asking a server, which *The home surface never waits on a source* forbids.
     */
    suspend fun reconcile(
        shelves: List<ServerShelf>,
        store: ShelfEditStore,
        progress: KavitaProgressStore,
        now: Long = System.currentTimeMillis(),
    ) {
        val fetched = shelves.mapNotNull { shelf ->
            val entries = members(shelf) ?: return@mapNotNull null
            Fetched(shelf, entries)
        }
        if (fetched.isEmpty()) return

        val queue = store.queue()
        val pull = ShelfPull.merging(
            remote = fetched.map { ShelfSnapshot(key(it.shelf), it.entries) },
            baseline = { queue.baseline(it) },
            pending = queue.edits,
        )

        var settled = queue.dropping(pull.toDrop)
        for (each in fetched) {
            settled = settled.recording(ShelfSnapshot(key(each.shelf), each.entries))
        }
        for (conflict in pull.conflicts) {
            // The server won, so what it overrode must never be sent afterwards: the edit
            // leaves the transport queue as well as this one.
            forget(conflict.discarded, progress)
            settled = settled.noting(
                ShelfConflictNotice(
                    shelf = conflict.shelf,
                    shelfName = shelves.firstOrNull { key(it) == conflict.shelf }?.title.orEmpty(),
                    discarded = conflict.discarded.map { it.title },
                    at = now,
                ),
            )
        }
        store.save(settled)

        push(pull.toPush, shelves, progress)
    }

    /**
     * What one shelf holds, named the way the thing that reads the record back joins on.
     *
     * A reading list answers with its chapters, in the server's order, because the order is
     * the list's meaning. A collection answers with the *names* of its series, in the order
     * the server listed them, because a collection groups series and this library's own idea
     * of a series is its name -- `LibraryRows` groups by nothing else, and a `Publication`
     * carries the name and no server series number at all. A series renamed on the server
     * drops out of the pinned shelf until the next reconciliation, which then writes the new
     * name down: the record heals itself, where a pin keyed on a title would not.
     *
     * Null where the server did not answer, so the caller can tell that apart from a shelf the
     * server says is empty.
     */
    private suspend fun members(shelf: ServerShelf): List<String>? {
        val client = KavitaClient(shelf.server.address)
        if (!shelf.isList) {
            return runCatching { client.collected(shelf.id) }.getOrNull()?.map { it.name }
        }
        val items = runCatching { client.readingListItems(shelf.id) }.getOrNull() ?: return null
        return items.sortedBy { it.order }.map { it.chapterId.toString() }
    }

    /**
     * Records an edit the server has not been told about yet.
     *
     * Written before the send is attempted rather than after it fails, because the two are
     * not the same promise: an app killed between the tap and the timeout has still had the
     * edit made in it. The next reconciliation settles it if it did in fact land.
     */
    fun note(
        entry: Int,
        title: String,
        shelf: ShelfKey,
        store: ShelfEditStore,
        at: Long = System.currentTimeMillis(),
    ) {
        store.update {
            it.queueing(ShelfEdit(shelf = shelf, entry = entry.toString(), title = title, madeAt = at))
        }
    }

    /**
     * How a server's shelf is named across a restart. The kind is in it because one server
     * numbers its collections and its reading lists from one apiece.
     */
    fun key(shelf: ServerShelf): ShelfKey = ShelfKey(
        shelf.server.id,
        shelf.id,
        if (shelf.isList) RememberedShelfKind.READING_LIST else RememberedShelfKind.COLLECTION,
    )

    /**
     * Where one entry of a server reading list currently sits.
     *
     * Both halves are needed and neither is the other: Kavita addresses a move by the *entry*
     * it minted, and this app knows the list by the chapters in it.
     */
    data class Place(val item: Int, val chapter: Int)

    /** One thing to ask the server for: move this entry from here to there. */
    data class Move(val item: Int, val from: Int, val to: Int)

    /**
     * The run of moves that turns the order a server holds into the order a reader made.
     *
     * Pure, and takes both sides as values, so the plan can be asserted without a server.
     * Each move is planned against the order the moves before it leave behind, because that
     * is the order the server will be in when it receives them -- planning every move against
     * the original positions sends coordinates the server has already invalidated.
     *
     * A wanted chapter the server does not hold is left out rather than moved: it is an entry
     * this device believes in and the server does not, which is the append queue's business,
     * not this one's. A held chapter the wanted order does not name keeps its place after the
     * ones that are named, because the server may have gained it since.
     *
     * iOS's `ShelfSync.moves` plans the same run.
     */
    fun moves(places: List<Place>, wanted: List<Int>): List<Move> {
        val current = places.toMutableList()
        val plan = mutableListOf<Move>()
        var target = 0
        for (chapter in wanted) {
            val at = current.indexOfFirst { it.chapter == chapter }
            if (at < target) continue
            if (at != target) {
                plan += Move(item = current[at].item, from = at, to = target)
                current.add(target, current.removeAt(at))
            }
            target += 1
        }
        return plan
    }

    /**
     * The rows of a server reading list, in the order the reader gave it.
     *
     * `collections-and-reading-lists` asks an edit made while the server is away to be
     * "applied locally" -- for a reorder that means the reader keeps looking at their own
     * order, not the server's, for as long as the server has not taken it.
     *
     * Rows the wanted order does not name follow the ones it does, in the order they arrived
     * in. Dropping them would lose a row the reader can see.
     */
    fun arranged(rows: List<ShelfEntry>, wanted: List<String>): List<ShelfEntry> {
        if (wanted.isEmpty()) return rows
        val named = wanted.mapNotNull { id -> rows.firstOrNull { it.id == id } }
        val taken = named.map { it.id }.toSet()
        return named + rows.filterNot { it.id in taken }
    }

    /** A drag on a server list: the order it makes, and the baseline a send checks first. */
    data class Drag(val order: List<Int>, val baseline: List<Int>)

    /**
     * Moves the row at [from] in [held] to [to]. Null when either place is not a row.
     *
     * Task 7.4: the baseline is the order the reader saw before this drag. When nothing is
     * held, that is the server's order: the order the list opened in, or the order of the
     * reader's last drag after the server took it. A baseline kept from when the screen
     * opened goes stale after the first drag the server takes, and every later drag of that
     * visit is then dropped as a conflict with the reader's own earlier drag.
     */
    fun dragged(held: List<String>, from: Int, to: Int): Drag? {
        if (from !in held.indices || to !in held.indices) return null
        val moved = held.toMutableList().apply { add(to, removeAt(from)) }
        return Drag(moved.mapNotNull { it.toIntOrNull() }, held.mapNotNull { it.toIntOrNull() })
    }

    /** The same key, from the shape the add-to sheet works in. */
    fun key(list: ServerList): ShelfKey = ShelfKey(list.server.id, list.id)

    /**
     * Sends what is still owed, through the queue that already carries writes to a server.
     *
     * [KavitaSync.flush] is the one push path -- a second one would double every append the
     * moment both ran. What is new is the moment it runs at: until now nothing asked for a
     * flush unless the reader opened that server's browser, so an edit made on the shelves
     * screen waited for a screen they had no reason to visit.
     */
    private suspend fun push(
        owed: List<ShelfEdit>,
        shelves: List<ServerShelf>,
        progress: KavitaProgressStore,
    ) {
        if (owed.isEmpty()) return
        for (id in owed.map { it.shelf.sourceId }.toSet()) {
            val page = shelves.firstOrNull { it.server.id == id }?.server ?: continue
            KavitaSync.flush(progress, id, page.address)
        }
    }

    /**
     * Takes discarded edits out of the transport queue, so a later flush cannot resurrect
     * what the server has already overruled.
     */
    private fun forget(discarded: List<ShelfEdit>, progress: KavitaProgressStore) {
        val dropped = discarded.map { "${it.shelf.shelfId}:${it.entry}" }.toSet()
        val held = progress.unsent().filter { unsent ->
            val list = unsent.listId ?: return@filter false
            "$list:${unsent.origin.chapterId}" in dropped
        }
        progress.sent(held)
    }
}
