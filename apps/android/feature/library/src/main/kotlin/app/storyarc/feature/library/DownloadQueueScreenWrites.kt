package app.storyarc.feature.library

import app.storyarc.core.model.Download
import app.storyarc.core.persistence.RemovedDownload
import java.util.UUID

/**
 * What a screen with no transfer to run may still do to the shared queue's record set --
 * reorder, record a copy that landed some other way, remove a finished download, undo that
 * removal, or take a source's downloads with it.
 *
 * Split out of [DownloadQueue] because that file is at the 800-line cap this project
 * enforces. Every one of these reads and writes [DownloadQueue._library], which is `internal`
 * rather than `private` for exactly this file: `offline-downloads` 1.1 makes the one app-level
 * queue the only writer of the download store, and a write these screens made to a fresh
 * [app.storyarc.core.persistence.DownloadStore] read instead would be undone the next time
 * the queue's own transfer path saved its cached copy. iOS's `DownloadQueueShared.swift` is
 * the same fix.
 */

/**
 * Moves a queued download one place earlier or later -- the write behind the Downloads
 * destination's reorder control.
 */
fun DownloadQueue.reorder(id: String, later: Boolean) {
    _library.value = _library.value.moving(id, later)
    store?.save(_library.value)
}

/**
 * Records a completed copy that arrived by some route other than this queue's own transfer --
 * a Kavita keep, or a local file copied straight in.
 *
 * [app.storyarc.core.model.DownloadLibrary.queueing] is a no-op once the id is already known,
 * exactly as it is for an ordinary enqueue: this does not re-copy a publication the reader
 * already has.
 */
fun DownloadQueue.record(download: Download) {
    _library.value = _library.value.queueing(download)
    store?.save(_library.value)
}

/**
 * Takes a finished publication's download off the device, reversibly. See
 * [app.storyarc.core.persistence.RemovedDownload].
 */
suspend fun DownloadQueue.removeAfterFinishing(id: String): RemovedDownload? {
    val store = store ?: return null
    val outcome = app.storyarc.core.persistence.removeAfterFinishing(store, _library.value, id)
        ?: return null
    _library.value = outcome.first
    return outcome.second
}

/** Puts a removed download back -- the Downloads destination's undo. */
suspend fun DownloadQueue.restore(removed: RemovedDownload) {
    _library.value = removed.undo(_library.value)
}

/**
 * Forgets every download a source contributed, deleting the files, for when the source
 * itself is removed.
 */
fun DownloadQueue.removingAll(sourceId: UUID): List<Download> {
    val (kept, removed) = _library.value.removingAll(sourceId)
    removed.forEach { store?.remove(it) }
    _library.value = kept
    store?.save(kept)
    return removed
}
