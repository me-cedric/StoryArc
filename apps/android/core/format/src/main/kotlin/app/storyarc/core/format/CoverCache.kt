package app.storyarc.core.format

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File

/**
 * Covers kept on disk, so a library that has been opened before opens without reading every
 * archive again.
 *
 * `sources` asks for a cover to be "stored on disk at display resolution for the device",
 * and for the cover cache to be "evictable under storage pressure independently of
 * downloaded publications". Both fall out of *where* this writes: the cache directory is
 * the one Android reclaims on its own, and downloads live in the app's files directory.
 * Clearing one has never touched the other, and the Privacy screen already counts and
 * clears this directory under "Cache".
 *
 * Until this existed the cover of every publication was decoded again on every launch — an
 * archive opened, an entry inflated and an image decoded, per cover, to draw a grid the
 * reader had already seen.
 *
 * iOS's `CoverCache` writes the same files for the same reasons.
 */
class CoverCache(private val directory: File) {

    /**
     * What a cover is written as.
     *
     * JPEG rather than the source's own format: a cover is a photograph-like image shown at
     * a few hundred density-independent pixels, the archive's PNG is often several
     * megabytes, and the point of this cache is to be cheaper than the thing it replaces.
     */
    private val quality = 85

    /**
     * Where one cover lives.
     *
     * Keyed by the pixel size as well as the publication, because "display resolution" is a
     * property of the device *and* the layout: the grid and the list ask for different
     * sizes, and a cover cached for one must not be served upscaled to the other.
     *
     * The identity is hashed rather than used directly. A publication id can carry a path,
     * and a path carries separators — a file name is not a place to find that out.
     */
    private fun file(id: String, maxPixelSize: Int): File {
        var hash = -0x340d631b7bdddcdbL // FNV-1a offset basis
        id.toByteArray().forEach { byte ->
            hash = (hash xor byte.toLong()) * 0x100000001b3L
        }
        return File(directory, "${hash.toString(36)}-$maxPixelSize.jpg")
    }

    /** The cover already on disk, if there is one at this size. */
    fun bitmap(id: String, maxPixelSize: Int): Bitmap? {
        val file = file(id, maxPixelSize)
        if (!file.isFile) return null
        return runCatching { BitmapFactory.decodeFile(file.path) }.getOrNull()
    }

    /**
     * Writes a cover, replacing whatever was there.
     *
     * Failure is silent and correct: this is a cache. A device with no room left should
     * draw the library, not refuse to.
     */
    fun store(bitmap: Bitmap, id: String, maxPixelSize: Int) {
        runCatching {
            directory.mkdirs()
            file(id, maxPixelSize).outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it)
            }
        }
    }

    /** Forgets every cover. The Privacy screen's "Clear cache", and the tests. */
    fun clear() {
        runCatching { directory.deleteRecursively() }
    }
}
