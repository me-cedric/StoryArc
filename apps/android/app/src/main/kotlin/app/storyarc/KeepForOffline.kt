package app.storyarc

import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.Download
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
        val extension = remote.substringAfterLast('.', "bin")
        val file = downloads.location(publication.id, extension)
        file.parentFile?.mkdirs()
        file.writeBytes(source.read(0, source.length.toInt()))

        downloads.save(
            downloads.library().queueing(
                Download(
                    id = publication.id,
                    title = publication.displayTitle,
                    remote = remote,
                    mediaType = "application/octet-stream",
                    state = Download.State.Finished,
                    downloadedBytes = file.length(),
                    expectedBytes = file.length(),
                ),
            ),
        )
        file.absolutePath
    }.getOrNull()
}
