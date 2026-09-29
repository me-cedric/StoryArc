package app.storyarc

import app.storyarc.core.format.ChunkedCopy
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.Download
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.feature.library.DownloadQueue
import app.storyarc.feature.library.record
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Copies a publication off a share and onto the device.
 *
 * `network-share`: when reconnection has failed for a minute "the app offers to download the
 * current publication for offline reading". This is that offer carried out -- the bytes are
 * fetched once and the reader reopens from the copy, so the rest of the session no longer
 * depends on the network.
 *
 * Returns where the copy landed, or null when the share is still unreachable, which is the
 * likeliest outcome and not a surprise: the offer exists because the network is down.
 *
 * Copied through [ChunkedCopy] rather than `file.writeBytes(source.read(0, source.length.toInt()))`:
 * `source.length.toInt()` overflows above 2 GiB, which used to write nothing and index an
 * empty file, and the single read is the same one-message-for-the-whole-file request the
 * share browser's own download made.
 */
suspend fun keepForOffline(
    queue: DownloadQueue,
    downloads: DownloadStore,
    publication: Publication,
    remote: String,
): String? {
    val kept = withContext(Dispatchers.IO) {
        runCatching {
            val source = PublicationAccess.remoteSource(remote) ?: return@runCatching null
            // The format's own media type, not `application/octet-stream`. The record and the
            // path are derived from the same value now, and a record that called every copy an
            // octet stream while the file on disk was named `.cbz` is exactly the disagreement
            // that let a removal miss the bytes.
            val extension = remote.substringAfterLast('.', "").lowercase()
            val mediaType = PublicationFormat.entries
                .firstOrNull { it.name.lowercase() == extension }
                ?.mediaType
                ?: "application/octet-stream"
            val file = downloads.location(publication.id, mediaType, publication.displayTitle)
            ChunkedCopy.copy(source, file)
            Download(
                id = publication.id,
                title = publication.displayTitle,
                remote = remote,
                mediaType = mediaType,
                state = Download.State.Finished,
                downloadedBytes = file.length(),
                expectedBytes = file.length(),
            ) to file.absolutePath
        }.getOrNull()
    } ?: return null
    // Recorded through the app-level queue, on the caller's thread, because the queue is the
    // only writer of the download store: a record saved beside it comes back out at its next
    // save -- dl-core 1.1.
    queue.record(kept.first)
    return kept.second
}
