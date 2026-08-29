package app.storyarc.feature.library

import android.content.ContentResolver
import android.net.Uri
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.BulkSelection
import app.storyarc.core.model.Download
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.persistence.DownloadStore
import java.io.File
import java.io.InputStream
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Downloading, for a publication that is already a file.
 *
 * `collections-and-reading-lists` asks for a selection to be downloaded and for the app to
 * state "the item count and total size before starting". Everything in the library came off
 * a folder the reader picked, so there is nothing to fetch -- but a picked folder is exactly
 * the thing that goes away. [LibraryViewModel.unavailableFolders] exists because it does: a
 * card comes out, a tree permission is revoked, and the shelf empties. `offline-downloads`
 * promises that what has been downloaded stays readable, and this is how a local publication
 * earns that promise: its bytes are copied into the app's own download store, recorded like
 * any other download, and are then visible, countable and removable in Settings.
 *
 * The same act as the app layer's `keepForOffline`, which does this for one publication on
 * an unreachable share. This is that path applied to a set. iOS's `KeepOffline.swift` is the
 * same file.
 */
internal object KeepOffline {

    /**
     * Which publications already have a copy of their own.
     *
     * Read when the reader asks rather than held: it is wanted twice in a confirmation and
     * never during a redraw, and a cached copy would disagree with Settings the moment a
     * download was removed there.
     */
    fun kept(store: DownloadStore): Set<String> = store.library().downloads.map { it.id }.toSet()

    /**
     * What a selection weighs on disk, for the confirmation that has to state a size.
     *
     * Nothing for a publication whose file cannot be measured, rather than a guess: the
     * requirement is that a size is *shown*, and an invented one is worse than a short one.
     */
    fun bytesOnDisk(resolver: ContentResolver, paths: List<String>): Long =
        paths.sumOf { path -> weigh(resolver, path) }

    /** Copies a whole selection into the download store, and reports what it copied. */
    suspend fun keep(
        resolver: ContentResolver,
        store: DownloadStore,
        publications: List<Publication>,
        selection: Set<String>,
        locate: (Publication) -> String?,
    ): Set<String> {
        val wanted = BulkSelection.downloading(selection, kept(store))
        store.prepare()

        val copied = mutableSetOf<String>()
        for (publication in publications) {
            if (publication.id !in wanted) continue
            // A folder of images has no single file to copy, and saying so by skipping it
            // beats copying a directory the reader never asked about.
            if (publication.format == PublicationFormat.IMAGE_FOLDER) continue
            val path = locate(publication) ?: continue
            val bytes = copy(resolver, store, publication, path) ?: continue
            record(store, publication, path, bytes)
            copied += publication.id
        }
        return copied
    }

    /** Forgets copies this made, deleting the files with them. */
    fun forget(store: DownloadStore, ids: Set<String>) {
        var library = store.library()
        for (id in ids) {
            val download = library[id] ?: continue
            store.delete(store.location(id, extensionOf(download.mediaType)))
            library = library.removing(id)
        }
        store.save(library)
    }

    /**
     * Puts one publication's bytes beside the other downloads.
     *
     * Named by identity, deliberately, and not by the title: Settings deletes a download by
     * looking for the file under the identity, so a copy filed under its title is a copy
     * that can be forgotten but not deleted.
     */
    private suspend fun copy(
        resolver: ContentResolver,
        store: DownloadStore,
        publication: Publication,
        path: String,
    ): Long? = withContext(Dispatchers.IO) {
        val target = store.location(publication.id, extensionOf(publication.format.mediaType))
        store.prepare(target)
        runCatching {
            // Replaced rather than refused: a copy left behind by a removal that only got
            // half way is not a reason to tell the reader their comic cannot be kept.
            target.delete()
            open(resolver, path)?.use { source ->
                target.outputStream().use { source.copyTo(it) }
            } ?: return@runCatching null
            target.length()
        }.getOrNull()
    }

    /** Writes the record that makes the copy a download rather than a stray file. */
    private fun record(store: DownloadStore, publication: Publication, path: String, bytes: Long) {
        store.save(
            store.library().queueing(
                Download(
                    id = publication.id,
                    sourceId = publication.sourceId,
                    title = publication.displayTitle,
                    // Where it came from, which for this one is the reader's own folder.
                    remote = path,
                    mediaType = publication.format.mediaType,
                    state = Download.State.Finished,
                    expectedBytes = bytes,
                    downloadedBytes = bytes,
                    completedAt = Date(),
                ),
            ),
        )
    }

    /**
     * The bytes behind a library publication.
     *
     * A document tree and a plain path, and nothing else. A publication read off a share is
     * kept offline by the app layer, which already holds the connection -- reading a remote
     * file through here would mean holding all of it in memory to write it back out.
     */
    private fun open(resolver: ContentResolver, path: String): InputStream? = when {
        PublicationAccess.isRemote(path) -> null
        PublicationAccess.isDocument(path) -> resolver.openInputStream(Uri.parse(path))
        else -> File(path).takeIf { it.isFile }?.inputStream()
    }

    private fun weigh(resolver: ContentResolver, path: String): Long = when {
        PublicationAccess.isRemote(path) -> 0L
        PublicationAccess.isDocument(path) -> runCatching {
            resolver.openAssetFileDescriptor(Uri.parse(path), "r")?.use { it.length }
        }.getOrNull()?.takeIf { it >= 0 } ?: 0L

        else -> File(path).takeIf { it.isFile }?.length() ?: 0L
    }

    private fun extensionOf(mediaType: String): String =
        PublicationFormat.ofMediaType(mediaType)?.name?.lowercase() ?: "bin"
}
