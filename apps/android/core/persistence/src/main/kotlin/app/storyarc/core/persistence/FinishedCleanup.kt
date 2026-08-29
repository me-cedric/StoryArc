package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.PublicationFormat
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A download taken off the device because its publication was finished.
 *
 * `offline-downloads`: with the setting on, finishing a publication removes its download,
 * "its progress is kept, and the removal is undoable for 10 seconds". Undoable is the hard
 * part: a file already deleted can only be put back by downloading it again, which is not
 * an undo. So the file is moved aside and only deleted when the ten seconds are up.
 */
data class RemovedDownload(
    val download: Download,
    /** Where the bytes are waiting, in case the reader changes their mind. */
    val aside: File,
    private val store: DownloadStore,
) {
    /** Puts the download back, bytes and record together. */
    suspend fun undo(library: DownloadLibrary): DownloadLibrary = withContext(Dispatchers.IO) {
        val home = store.location(download)
        aside.renameTo(home)
        library.queueing(download).also(store::save)
    }

    /** Lets it go. Called when nobody undid it. */
    suspend fun settle() = withContext(Dispatchers.IO) { aside.delete() }
}

/**
 * The first download whose file the reader has finished, if any.
 *
 * Matched by the file's own path rather than by the publication id. A download's id is
 * whatever the catalogue called it; the progress record is written by the reader against
 * the local file it opened, and the download store is what knows those two are the same
 * thing.
 *
 * An imported copy is never one of them. `offline-downloads` sweeps a download away because
 * "the catalogue can be asked for it again", and nothing can be asked for an import --
 * `local-library` promises the copy outlives the original, so deleting it on the last page
 * would be the app breaking its own promise.
 */
suspend fun finishedDownload(
    store: DownloadStore,
    library: DownloadLibrary,
    isFinished: suspend (String) -> Boolean,
): Download? = withContext(Dispatchers.IO) {
    library.finished.filterNot(ImportedCopies::isImported).firstOrNull { download ->
        val path = store.location(download).absolutePath
        isFinished(path)
    }
}

/**
 * Takes a finished publication's download off the device, reversibly.
 *
 * Null when there was nothing to remove, which is the common case: most publications a
 * reader finishes were never downloaded.
 */
suspend fun removeAfterFinishing(
    store: DownloadStore,
    library: DownloadLibrary,
    publicationId: String,
): Pair<DownloadLibrary, RemovedDownload>? = withContext(Dispatchers.IO) {
    val download = library[publicationId] ?: return@withContext null
    val home = store.location(download)
    if (!home.exists()) return@withContext null

    // Moved, not deleted. The record goes now so the library stops calling it downloaded;
    // the bytes wait until the undo window closes.
    val aside = File(home.parentFile, "${home.name}.removing")
    if (!home.renameTo(aside)) return@withContext null

    val without = library.removing(publicationId)
    store.save(without)
    without to RemovedDownload(download, aside, store)
}

private fun extensionOf(mediaType: String): String =
    PublicationFormat.ofMediaType(mediaType)?.name?.lowercase() ?: "bin"
