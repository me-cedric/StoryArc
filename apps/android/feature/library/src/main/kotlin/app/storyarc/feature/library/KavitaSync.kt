package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaPosition
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaExchange
import app.storyarc.core.kavita.KavitaOwed
import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.KavitaUnsent

/**
 * Telling a Kavita server where the reader got to.
 *
 * `kavita-server` asks for the position to be sent when the reader leaves, and "retried on
 * the next successful connection if it fails". Two operations, because those are the two
 * moments: one when a chapter is closed, one when a server is reachable again.
 */
object KavitaSync {

    /**
     * The server a pull is talking to, when it was given one.
     *
     * The two travel together because neither is any use alone here: an address says where to
     * send, and the source says which of the queued writes belong to it.
     */
    private class Server(val id: String, val address: KavitaAddress)

    /** Sends one position, keeping it for later if the server is not there. */
    suspend fun report(
        store: KavitaProgressStore,
        address: KavitaAddress?,
        origin: KavitaOrigin,
        page: Int,
    ) {
        val unsent = KavitaUnsent(origin, page)
        if (address == null) return store.hold(unsent)
        val sent = runCatching { KavitaClient(address).report(position(origin, page)) }
        if (sent.isFailure) store.hold(unsent)
    }

    /** Sends one deliberate mark, keeping it for later if the server is not there. */
    /**
     * Takes what the server says other devices have read, and merges it in.
     *
     * `reading-progress`: "progress recorded on other devices is merged into the local
     * store". The rules are ADR-0006's and live in [ProgressPull]; what is here is the part
     * only this source can do -- turning a chapter's `pagesRead` into a position, and
     * finding which publication on this device that chapter was read as.
     *
     * A chapter this device has never opened is skipped rather than adopted. The position is
     * real and the publication is not: the library holds nothing to attach it to, and
     * inventing an identity for it would be inventing a reading.
     *
     * A pull that finds the server *behind* sends the local position back, which is the half
     * of `reading-progress`'s synchronisation requirement that used to be computed and
     * dropped on the floor. Give it the server it is talking to and it goes out now; give it
     * nothing and the position waits in the same queue a failed report waits in, because
     * `sources` calls an unreachable server a normal state rather than a failure.
     *
     * Returns the conflicts, which are the only part a caller has to say anything about.
     */
    suspend fun pull(
        chapters: List<KavitaChapter>,
        kavita: KavitaProgressStore,
        progress: ProgressStore,
        sourceId: String? = null,
        address: KavitaAddress? = null,
    ): List<ProgressPull.Conflict> {
        val remote = mutableListOf<ReadingProgress>()
        val local = mutableMapOf<String, ReadingProgress>()
        val reported = mutableMapOf<String, KavitaChapter>()
        val origins = mutableMapOf<String, KavitaOrigin>()

        for (chapter in chapters) {
            if (chapter.pages <= 0) continue
            val publicationId = kavita.publicationForChapter(chapter.id) ?: continue
            val held = progress.progressForStableId(publicationId) ?: continue
            val key = held.identity.stableId
            local[key] = held
            reported[key] = chapter
            kavita.origin(publicationId)?.let { origins[key] = it }
            // The server's position, wearing the local record's identity -- which is the
            // only thing that lets the two be compared at all.
            remote += held.copy(
                position = KavitaExchange.position(chapter.pagesRead, chapter.pages),
                updatedAtEpochMillis = System.currentTimeMillis(),
            )
        }

        val pull = ProgressPull.merging(remote) { local[it.stableId] }
        val exchange = KavitaExchange.of(pull, reported)
        exchange.toSave.forEach { progress.save(it) }
        val server = if (sourceId != null && address != null) Server(sourceId, address) else null
        settle(exchange.owed, origins, server, kavita, progress)
        return pull.conflicts
    }

    /**
     * Tells the server what the merge says it is behind on, and writes down what it took.
     *
     * Queued before the send is attempted rather than after it fails, for the reason
     * [ShelfSync.note] gives: an app killed between the two has still had the reading done in
     * it. [flush] is then the one push path, as it is for a reading-list edit -- a second one
     * would double every write the moment both ran.
     *
     * Only a position the server actually took is stamped as synchronised. One it did not
     * stays exactly as it was and waits for the next flush, so an evening's reading offline
     * is a queue entry rather than a lost place and never an error the reader has to read.
     */
    private suspend fun settle(
        owed: List<KavitaOwed>,
        origins: Map<String, KavitaOrigin>,
        server: Server?,
        kavita: KavitaProgressStore,
        progress: ProgressStore,
    ) {
        if (owed.isEmpty()) return

        for (each in owed) {
            val origin = origins[each.settled.identity.stableId] ?: continue
            kavita.hold(KavitaUnsent(origin, each.pageNum))
        }

        // No server named means there is nowhere to send and nothing more to do -- the queue
        // above is the whole promise until one turns up.
        if (server == null) return
        val delivered = flush(kavita, server.id, server.address)
            .filter { it.mark == null && it.listId == null }
            .map { it.origin.chapterId }
            .toSet()
        owed.filter { it.chapterId in delivered }.forEach { progress.save(it.settled) }
    }

    suspend fun mark(
        store: KavitaProgressStore,
        address: KavitaAddress?,
        origin: KavitaOrigin,
        isRead: Boolean,
    ) {
        val unsent = KavitaUnsent(origin, page = 0, mark = isRead)
        if (address == null) return store.hold(unsent)
        val sent = runCatching { send(KavitaClient(address), unsent) }
        if (sent.isFailure) store.hold(unsent)
    }

    /** Appends a chapter to one of the server's reading lists, holding it if the server is not there. */
    suspend fun append(
        store: KavitaProgressStore,
        address: KavitaAddress?,
        origin: KavitaOrigin,
        listId: Int,
    ) {
        val unsent = KavitaUnsent(origin, page = 0, listId = listId)
        if (address == null) return store.hold(unsent)
        val sent = runCatching { send(KavitaClient(address), unsent) }
        if (sent.isFailure) store.hold(unsent)
    }

    /**
     * Sends everything held for one server.
     *
     * Held positions that still fail stay held. A server that is down now was down when the
     * chapter was read, and forgetting the position would lose exactly the reader whose
     * connection this feature exists for.
     *
     * Returns what the server took, so a caller that needs to write down the fact of the
     * exchange can tell it apart from what is still waiting.
     */
    suspend fun flush(
        store: KavitaProgressStore,
        sourceId: String,
        address: KavitaAddress,
    ): List<KavitaUnsent> {
        val waiting = store.unsent().filter { it.origin.sourceId == sourceId }
        if (waiting.isEmpty()) return emptyList()

        val client = KavitaClient(address)
        val delivered = waiting.filter { held -> runCatching { send(client, held) }.isSuccess }
        store.sent(delivered)
        return delivered
    }

    private suspend fun send(client: KavitaClient, held: KavitaUnsent) {
        val listId = held.listId
        val mark = held.mark
        when {
            listId != null ->
                client.append(listId, held.origin.seriesId, listOf(held.origin.chapterId))
            mark != null -> client.mark(held.origin.seriesId, held.origin.chapterId, mark)
            else -> client.report(position(held.origin, held.page))
        }
    }

    private fun position(origin: KavitaOrigin, page: Int) = KavitaPosition(
        libraryId = origin.libraryId,
        seriesId = origin.seriesId,
        volumeId = origin.volumeId,
        chapterId = origin.chapterId,
        pageNum = page,
    )
}
