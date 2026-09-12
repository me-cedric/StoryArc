package app.storyarc.feature.reader

import android.content.ContentResolver
import android.util.Log
import app.storyarc.core.format.PublicationAccess
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
 * Nothing here touches the page list, the position, the decoded pages or the thumbnails. The
 * whole switch is [app.storyarc.core.format.AdoptingArchive] taking a new source, and the
 * reader learns nothing about it -- which is what "without interrupting" means.
 *
 * @return whether the reader is now reading from [path].
 */
suspend fun ReaderViewModel.adoptLocalCopy(
    resolver: ContentResolver,
    path: String,
): Boolean {
    val reading = archive ?: return false
    // Opened before the swap, off the main thread, because reading a central directory is
    // still file work -- and refused rather than thrown, because a local copy that will not
    // open is not a reason to take a working stream away from somebody mid-page.
    val local = runCatching { withContext(Dispatchers.IO) { PublicationAccess.openArchive(resolver, path) } }
        .getOrElse { cause ->
            Log.w(TAG_ADOPTION, "the copy that arrived will not open; still streaming", cause)
            return false
        }
    return reading.adopt(local)
}

private const val TAG_ADOPTION = "ReaderAdoption"
