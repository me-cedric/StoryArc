package app.storyarc.feature.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A server's own artwork, kept in the same disk cache a local publication's cover is.
 *
 * Task 22.2 — the owner's field report on v0.1.1: "Kavita collections and reading lists on
 * Home show only a title, no cover." [HomeShelfArtwork][app.storyarc.HomeDestination] (Home)
 * and [ServerShelfCover] (the Shelves screen) answered that by fetching Kavita's cover routes
 * directly, every time either card entered composition — a card scrolled out of a `LazyRow`
 * and back, a visit to Home, a relaunch, each asked the server again for bytes it had already
 * decoded once. Neither wrote what it decoded anywhere, which is the reviewer's own
 * correction on this task: "through the authenticated client and the cover cache" named a
 * cache neither card used.
 *
 * [id] is the caller's to scope: a Kavita series id and a Kavita chapter id are both small
 * integers, two different servers answer the same one, and [LibraryViewModel.coverCache]
 * hashes whatever string it is handed — so a caller that does not prefix its own kind and
 * source folds a series cover and a chapter cover from two different servers onto one file.
 */
suspend fun LibraryViewModel.serverCover(
    id: String,
    maxPixelSize: Int,
    fetch: suspend () -> ByteArray,
): Bitmap? {
    withContext(Dispatchers.IO) { coverCache.bitmap(id, maxPixelSize) }?.let { return it }

    val bytes = runCatching { fetch() }.getOrNull()?.takeIf { it.isNotEmpty() } ?: return null
    val bitmap = withContext(Dispatchers.IO) {
        runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    } ?: return null

    withContext(Dispatchers.IO) { coverCache.store(bitmap, id, maxPixelSize) }
    return bitmap
}
