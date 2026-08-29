package app.storyarc

import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.Download
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.DownloadStore
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
 */
suspend fun keepForOffline(
    downloads: DownloadStore,
    publication: Publication,
    remote: String,
): String? = withContext(Dispatchers.IO) {
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
        file.parentFile?.mkdirs()
        file.writeBytes(source.read(0, source.length.toInt()))

        downloads.save(
            downloads.library().queueing(
                Download(
                    id = publication.id,
                    title = publication.displayTitle,
                    remote = remote,
                    mediaType = mediaType,
                    state = Download.State.Finished,
                    downloadedBytes = file.length(),
                    expectedBytes = file.length(),
                ),
            ),
        )
        file.absolutePath
    }.getOrNull()
}
