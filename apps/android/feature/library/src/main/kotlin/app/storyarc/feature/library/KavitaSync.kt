package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaPosition
import app.storyarc.core.persistence.KavitaOrigin
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

    /**
     * Sends everything held for one server.
     *
     * Held positions that still fail stay held. A server that is down now was down when the
     * chapter was read, and forgetting the position would lose exactly the reader whose
     * connection this feature exists for.
     */
    suspend fun flush(store: KavitaProgressStore, sourceId: String, address: KavitaAddress) {
        val waiting = store.unsent().filter { it.origin.sourceId == sourceId }
        if (waiting.isEmpty()) return

        val client = KavitaClient(address)
        val delivered = waiting.filter { held ->
            runCatching { client.report(position(held.origin, held.page)) }.isSuccess
        }
        store.sent(delivered)
    }

    private fun position(origin: KavitaOrigin, page: Int) = KavitaPosition(
        libraryId = origin.libraryId,
        seriesId = origin.seriesId,
        volumeId = origin.volumeId,
        chapterId = origin.chapterId,
        pageNum = page,
    )
}
