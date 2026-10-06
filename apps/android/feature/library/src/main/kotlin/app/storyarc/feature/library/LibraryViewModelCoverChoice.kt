package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import app.storyarc.core.format.CoverArtwork
import app.storyarc.core.format.CoverLadder
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.model.Publication
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * What the reader can do about a publication's cover, and where the ladder's top rung lives.
 *
 * Tasks 1.3, 2.1, 2.2 and 2.4 of `cover-for-every-publication`, beside [LibraryViewModel]
 * rather than inside it for the reason `LibraryViewModelAudiobookCover.kt` is beside it: that
 * file is at the line cap this repository enforces, so new behaviour goes in a new file next
 * to it. iOS's `CoverChoice.swift` is its twin.
 */

/**
 * Where chosen covers are kept: the app's own data directory, never a cache directory.
 *
 * Task 2.5 in one line. `StorageUsage.clearCache` empties `cacheDir` and `externalCacheDir`,
 * and a cover the reader chose is not a cache — nothing can recreate it.
 */
internal val LibraryViewModel.coverOverrideDirectory: File
    get() = CoverOverrideStore.directoryIn(getApplication<Application>().filesDir)

/** The ladder the shelf, the player and the publication page all ask. */
internal val LibraryViewModel.coverLadder: CoverLadder
    get() = CoverLadder(CoverOverrideStore(coverOverrideDirectory))

/**
 * The reader's own picture, remembered as the shelf's own cover once it is decoded.
 *
 * Asked before either cache in [LibraryViewModel.cover], because both are keyed by identity
 * and size alone: a cover chosen after one was drawn would otherwise be answered with the one
 * it replaced. It is also the only rung a server row can reach, since such a row has no file
 * on this device for the rungs below to read.
 */
internal suspend fun LibraryViewModel.chosenCover(
    publication: Publication,
    maxPixelSize: Int,
): Bitmap? {
    val chosen = withContext(Dispatchers.IO) {
        coverLadder.chosenCover(publication, maxPixelSize)
    } ?: return null
    covers[publication.id] = chosen
    return chosen
}

/** Whether the reader has chosen this publication's cover themselves. */
internal fun LibraryViewModel.hasChosenCover(publication: Publication): Boolean =
    CoverOverrideStore(coverOverrideDirectory).file(publication) != null

/**
 * Whether moving this publication would lose the cover the reader chose.
 *
 * `cover-art`'s *A publication with no digest*: a folder of images and a server row carry no
 * content digest, so their override is filed under the stable identifier — which is the path —
 * and a move breaks it. The page says so plainly rather than letting the choice disappear
 * without explanation.
 */
internal fun LibraryViewModel.chosenCoverIsTiedToPath(publication: Publication): Boolean =
    CoverOverrideStore(coverOverrideDirectory).keyKind(publication) ==
        CoverOverrideStore.Key.STABLE_IDENTIFIER

/**
 * Records a picture the reader picked as this publication's cover.
 *
 * The picture is cropped to the cover shape first, because the ladder's other rungs all answer
 * with artwork that already is that shape and a photograph is not.
 *
 * @return whether the picture was stored. False is a picture this device cannot decode, or a
 *   write that failed; the caller tells the reader rather than leaving a button that appears
 *   to do nothing.
 */
internal suspend fun LibraryViewModel.setCover(
    picture: ByteArray,
    publication: Publication,
): Boolean {
    val stored = withContext(Dispatchers.IO) {
        val shaped = CoverArtwork.coverShaped(picture) ?: return@withContext false
        CoverOverrideStore(coverOverrideDirectory).store(shaped, publication) != null
    }
    if (stored) forgetDrawnCover(publication)
    return stored
}

/**
 * Removes the cover the reader chose, and deletes the image.
 *
 * The ladder resolves the publication's cover again from the rung below on the next draw,
 * which is what `cover-art`'s *Undoing the choice* asks for.
 */
internal suspend fun LibraryViewModel.removeChosenCover(publication: Publication) {
    // Off the main thread: the store deletes a file and the cover cache lists its directory.
    withContext(Dispatchers.IO) { CoverOverrideStore(coverOverrideDirectory).remove(publication) }
    forgetDrawnCover(publication)
}

/**
 * Drops every copy of this publication's artwork that something has already drawn.
 *
 * Both caches, not one. [LibraryViewModel.covers] is what the shelf is holding this launch and
 * [LibraryViewModel.coverCache] is what it will read on the next one — leaving either behind
 * shows the reader the cover they just replaced, which reads as the choice not having worked.
 */
private suspend fun LibraryViewModel.forgetDrawnCover(publication: Publication) {
    // Every copy of one file shares one chosen cover, because the store keys it by digest, so
    // every copy is redrawn -- not only the one the reader acted on.
    val digest = publication.identity.contentDigest
    val ids = publications.value
        .filter { digest != null && it.identity.contentDigest == digest }
        .map { it.id }
        .plus(publication.id)
        .distinct()
    for (id in ids) {
        covers.remove(id)
        withContext(Dispatchers.IO) { coverCache.removeEverySize(id) }
        coverRevisions[id] = (coverRevisions[id] ?: 0) + 1
    }
}

/**
 * How many times this publication's cover has changed this launch. A view that holds a decoded
 * cover keys its load on this, so a cover the reader chooses or removes is redrawn wherever it
 * is on screen -- the two-pane layout keeps the shelf beside the page that changed it.
 */
internal fun LibraryViewModel.coverRevision(publication: Publication): Int =
    coverRevisions[publication.id] ?: 0
