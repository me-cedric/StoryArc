package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.ShelfConflictNotice
import app.storyarc.core.model.ShelfEdit
import app.storyarc.core.model.ShelfKey
import app.storyarc.core.model.ShelfPull
import app.storyarc.core.model.ShelfSnapshot
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ShelfEditStore

/**
 * Keeping a server-backed reading list and the edits owed to it in step.
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

    /** One reading list, as the server currently has it. */
    private data class Fetched(val shelf: ServerShelf, val entries: List<String>)

    /**
     * Reconciles every server reading list that will answer.
     *
     * A list that does not answer is simply absent from what is merged, which leaves its
     * edits queued and says nothing about them -- that is the unreachable server, and
     * `sources` is explicit that it is a normal state rather than a failure.
     */
    suspend fun reconcile(
        lists: List<ServerShelf>,
        store: ShelfEditStore,
        progress: KavitaProgressStore,
        now: Long = System.currentTimeMillis(),
    ) {
        val fetched = lists.mapNotNull { shelf ->
            val client = KavitaClient(shelf.server.address)
            val items = runCatching { client.readingListItems(shelf.id) }.getOrNull()
                ?: return@mapNotNull null
            Fetched(shelf, items.sortedBy { it.order }.map { it.chapterId.toString() })
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
                    shelfName = lists.firstOrNull { key(it) == conflict.shelf }?.title.orEmpty(),
                    discarded = conflict.discarded.map { it.title },
                    at = now,
                ),
            )
        }
        store.save(settled)

        push(pull.toPush, lists, progress)
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

    /** How a server's reading list is named across a restart. */
    fun key(shelf: ServerShelf): ShelfKey = ShelfKey(shelf.server.id, shelf.id)

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
        lists: List<ServerShelf>,
        progress: KavitaProgressStore,
    ) {
        if (owed.isEmpty()) return
        for (id in owed.map { it.shelf.sourceId }.toSet()) {
            val page = lists.firstOrNull { it.server.id == id }?.server ?: continue
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
