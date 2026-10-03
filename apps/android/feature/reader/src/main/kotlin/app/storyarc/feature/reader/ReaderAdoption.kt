package app.storyarc.feature.reader

import android.content.ContentResolver
import android.util.Log
import app.storyarc.core.format.AdoptingArchive
import app.storyarc.core.format.ComicArchiveReading
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.ReadingPosition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Reads from the copy that has just arrived, without interrupting the reader.
 *
 * `offline-downloads`' *Reading while downloading*: a publication opened by streaming
 * "switches to the local copy when the download completes, without interrupting reading".
 *
 * An extension rather than a method because [ReaderViewModel] is at its line cap, and a file
 * that may not grow is a file where the next thing to be added is added somewhere else.
 *
 * Nothing here touches the page list, the position, the decoded pages or the thumbnails for a
 * reader already streaming successfully. The whole switch is [AdoptingArchive] taking a new
 * source, and the reader learns nothing about it -- which is what "without interrupting" means.
 *
 * dl-core 1.7: when [ReaderViewModel.archive] is null, the stream never opened at all -- a
 * server with no range support, say -- and there is nothing to adopt *into*. That case opens
 * the arrived file directly, through [applyOpenedArchive], the same success path a working
 * stream would have run.
 *
 * @return whether the reader is now reading from [path].
 */
suspend fun ReaderViewModel.adoptLocalCopy(
    resolver: ContentResolver,
    path: String,
): Boolean {
    val opened = runCatching { withContext(Dispatchers.IO) { PublicationAccess.openArchive(resolver, path) } }
        .getOrElse { cause ->
            Log.w(TAG_ADOPTION, "the copy that arrived will not open", cause)
            // A reader that waited has no stream to fall back on, so its wait ends here.
            endWaitIfDownloadStopped()
            return false
        }
    val reading = archive
    if (reading == null) {
        if (!isWaitingForDownload.value) return false
        applyOpenedArchive(opened)
        _isWaitingForDownload.value = false
        return true
    }
    return reading.adopt(opened)
}

/**
 * Ends a wait for a download as the ordinary failure, once the download is no longer on its way.
 *
 * dl-core 1.7: `offline-downloads` marks a failed download "failed with a plain-language
 * reason", and a wait that never ends says nothing. A download that failed, was removed, or
 * landed as a copy that will not open all end here. Nothing happens while the reader is not
 * waiting, or while its download is still on its way.
 */
fun ReaderViewModel.endWaitIfDownloadStopped() {
    if (!isWaitingForDownload.value || isDownloadPending()) return
    _isWaitingForDownload.value = false
    _failure.value = ReaderFailure(R.string.reader_cannot_open)
}

/**
 * Puts a freshly opened archive in place: the page list, the designated cover, a recorded
 * position, and the cover colours -- the same success path [ReaderViewModel.open] runs for a
 * stream that opened. Shared with [adoptLocalCopy]'s waiting-state branch, which reaches this
 * from a stream that never opened at all.
 */
internal suspend fun ReaderViewModel.applyOpenedArchive(opened: ComicArchiveReading) {
    archive = AdoptingArchive(opened)
    _pages.value = opened.pages
    _skippedPageCount.value = opened.skippedPageCount
    wide.addAll(opened.doublePageIndices)
    publication.coverPath?.let { path ->
        val index = opened.pages.indexOfFirst { it.path == path }
        if (index >= 0) initialIndex = index
    }
    // A recorded position wins over the cover, unless it is finished -- `reading-progress`
    // reopens a finished publication "at the beginning while retaining the finished record".
    val record = progress?.progress(publication.identity)
    val recorded = record?.position?.takeUnless { record.isFinished }
    if (recorded is ReadingPosition.Page && recorded.index in opened.pages.indices) {
        initialIndex = recorded.index
    }
    deriveCoverColours()
}

private const val TAG_ADOPTION = "ReaderAdoption"
