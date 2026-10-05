package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.Download
import app.storyarc.core.model.PublicationFormat
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.update

/**
 * Downloading a Kavita chapter, which is a download like any other and was not one.
 *
 * `offline-downloads` 1.9: keeping a chapter read the whole body into memory, wrote it to a
 * cache file and moved it into the download store by hand. So a kept chapter had no row in the
 * downloads view, no pause, no resume, no retry and no share of the concurrency bound -- the
 * four things *Queue management* asks for -- and a six-hundred-megabyte collected edition was a
 * six-hundred-megabyte byte array. The queue already streams a transfer to disk, so the fix is
 * to let a chapter in rather than to build a second transfer beside it.
 *
 * Its own file because [DownloadQueue] is at the 800-line cap this project enforces, the same
 * reason `DownloadQueueScreenWrites.kt` is its own, and it reaches the same `internal` members.
 *
 * iOS's `DownloadQueueKavita.swift` is the same entry point.
 */

/**
 * This download's finished file, when there is one on disk.
 *
 * Keyed by the download's own id rather than by a catalogue entry, because a Kavita chapter has
 * no entry. [DownloadQueue.downloaded] resolves an entry to an id and then asks this.
 */
internal fun DownloadQueue.fileOf(id: String): File? {
    val download = _library.value[id]?.takeIf { it.state.isFinished } ?: return null
    return store?.location(download)?.takeIf { it.exists() }
}

/**
 * The same download, with the media type the bytes actually have.
 *
 * **The destination's extension is chosen from the record, and one source cannot state it at
 * enqueue.** Kavita serves comics and books from one `Download/chapter` route and names the
 * type only in the response, so a chapter is enqueued with an empty media type. Where the
 * record names no format this asks the bytes, which is the one answer that cannot be a guess --
 * and a guess here is what wrote an EPUB under `.cbz` and handed it to the comic reader.
 *
 * A record that already names a format is returned untouched, so an OPDS download still lands
 * under the type its acquisition link declared and pays for no extra read. A sniff that throws
 * is left to the verification index after the move, which words the refusal.
 */
internal suspend fun DownloadQueue.typed(download: Download, arrived: File): Download {
    if (PublicationFormat.ofMediaType(download.mediaType) != null) return download
    val sniffed = runCatching { PublicationIndexer.index(arrived).format.mediaType }.getOrNull()
        ?: return download
    _library.update { it.typing(download.id, sniffed) }
    return download.copy(mediaType = sniffed)
}

/**
 * Queues a Kavita chapter and waits for its file, as [DownloadQueue.fetch] does for a
 * catalogue entry.
 *
 * @param id the record's id, which is what the *source* calls the chapter --
 *   `kavita:<source>:<chapter>`. The card and the fold are filed under it, so the caller spells
 *   it rather than this.
 * @param credential the bearer token for this one transfer. Held until the transfer ends, for
 *   the reason [DownloadQueue.given] gives, and dropped here when it does.
 * @return the landed file, or null when the transfer failed -- the queue has recorded the
 *   reason by then, so the caller says nothing more about it.
 */
suspend fun DownloadQueue.fetchChapter(
    id: String,
    title: String,
    remote: String,
    sourceId: UUID?,
    credential: OpdsCredential,
    seriesHint: String? = null,
): File? {
    fileOf(id)?.let { return it }
    given[id] = credential
    hints[id] = seriesHint
    val waiter = CompletableDeferred<File?>()
    waiting.getOrPut(id) { mutableListOf() }.add(waiter)
    val existing = _library.value[id]
    if (existing == null) {
        _library.value = _library.value.queueing(
            Download(
                id = id,
                sourceId = sourceId,
                title = title,
                remote = remote,
                // Empty on purpose. The server states it in the response and [typed] writes it
                // down once the bytes are here.
                mediaType = "",
            ),
        )
        store?.save(_library.value)
        reconsider()
    } else {
        // A chapter the reader asked for again after it failed or was paused. `queueing` is a
        // no-op once a record exists and neither state resolves itself -- the same rule
        // [DownloadQueue.fetch] follows.
        resume(id)
    }
    promote(id)
    return waiter.await().also { given -= id }
}
