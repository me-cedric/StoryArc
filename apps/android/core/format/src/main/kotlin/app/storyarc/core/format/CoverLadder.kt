package app.storyarc.core.format

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import app.storyarc.core.model.Publication
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt

/**
 * The one place that answers "what is this publication's cover".
 *
 * Task 1.3 of `cover-for-every-publication`. The shelf, the player, the media session and the
 * publication page each resolved covers for themselves, so a new rung had to be taught to four
 * callers or it reached three of them — which is how a reader could choose a cover, see it on
 * the shelf, and still get a glyph on the car's own screen. They ask this instead.
 *
 * The rungs, cheapest first, exactly as `cover-art`'s *The cover ladder* orders them:
 *
 * 1. **The reader's own picture**, from [CoverOverrideStore]. It is above the bytes rather
 *    than below them because the reader chose it over what the bytes say.
 * 2. **The publication's own bytes**, through [PublicationAccess.anyCover].
 * 3. **A loose cover image beside the file**, through [LooseCover].
 *
 * What is deliberately *not* here is the server rung and the lookup rung. A Kavita chapter's
 * cover needs that source's credential and its certificate pins, which belong to the library
 * rather than to the format layer; `LibraryViewModel.cover` keeps that rung where its
 * dependencies already are, and asks this one for everything on the device. iOS's
 * `CoverLadder.swift` is its twin.
 */
class CoverLadder(private val overrides: CoverOverrideStore) {

    /**
     * The reader's own picture for this publication, decoded and bounded, or null where they
     * have chosen none.
     *
     * The top rung on its own, for a caller that holds a cache of its own in front of the
     * ladder: `LibraryViewModel.cover` reads a decoded cover off disk by identity and size,
     * and that cache cannot know a reader replaced the picture behind it. Asking this first is
     * what makes a chosen cover appear at once rather than on the next cache clear, and it is
     * also the only rung a server row can reach — such a row has no file on this device for
     * the rungs below to read.
     */
    fun chosenCover(publication: Publication, maxPixelSize: Int): Bitmap? {
        val data = overrides.bytes(publication) ?: return null
        return runCatching { PageDecoder.decode(data, maxPixelSize) }.getOrNull()
    }

    /**
     * The publication's cover, decoded and bounded, or null where no rung answers.
     *
     * Null rather than a throw: every caller draws `CoverlessWell` for an absent cover, and a
     * missing cover is a normal state rather than a failure. [path] is where the library
     * recorded this publication; null is a server row, which has no file on this device — its
     * override still answers, which is what lets a reader set a cover on one.
     */
    suspend fun cover(
        resolver: ContentResolver,
        publication: Publication,
        path: String?,
        maxPixelSize: Int,
    ): Bitmap? {
        chosenCover(publication, maxPixelSize)?.let { return it }
        if (path == null) return null
        runCatching { PublicationAccess.anyCover(resolver, publication, path, maxPixelSize) }
            .getOrNull()
            ?.let { return it }
        val loose = looseCover(path) ?: return null
        return runCatching { PageDecoder.decode(loose.readBytes(), maxPixelSize) }.getOrNull()
    }

    /**
     * The file the publication's artwork lives in, for a caller that needs a path rather than
     * pixels — the media session hands one to the system, which draws it itself.
     *
     * The same ladder, stopping at the rungs that are already files: a chosen cover, the
     * artwork the indexer wrote out for an audiobook, then a loose image beside the file. A
     * comic's cover is an entry inside an archive and has no path of its own, so this answers
     * null for one — which is what it answered before this existed.
     */
    fun coverFile(publication: Publication, path: String?): File? {
        overrides.file(publication)?.let { return it }
        val recorded = publication.coverPath
        if (recorded != null && publication.format.isAudio) {
            File(recorded).takeIf { it.isFile }?.let { return it }
        }
        return looseCover(path)
    }

    /**
     * A loose image beside a recorded path, where that path names something on the filesystem.
     *
     * A Storage Access Framework document has no filesystem path to look beside, so a loose
     * cover on a SAF path is found at index time instead, where the scanner already holds the
     * folder's own listing — see `LibraryScanner.indexDocumentFolder`. Answering null here for
     * such a path is therefore the right answer rather than a gap: by the time anything asks
     * this, the copy already made is the publication's recorded cover.
     */
    private fun looseCover(path: String?): File? {
        if (path == null || PublicationAccess.isDocument(path) || PublicationAccess.isRemote(path)) {
            return null
        }
        return LooseCover.beside(File(path))
    }
}

/**
 * Turning a picture the reader picked into a cover.
 *
 * `cover-art`: "the chosen picture is cropped to the cover shape before it is stored". A
 * photograph is 4:3 or 3:4 and a cover is 2:3, so an uncropped choice is letterboxed into every
 * cell on the shelf beside covers that are not — the artwork is the interface, and a shelf
 * where one cell has grey bars down its sides is a shelf with a mistake on it.
 */
object CoverArtwork {

    /** The printed proportion every cover-shaped cell in this app draws. */
    const val ASPECT_RATIO = 2f / 3f

    private const val QUALITY = 90

    /** The rectangle a picture of this size is cut down to. */
    data class Crop(val x: Int, val y: Int, val width: Int, val height: Int)

    /**
     * Where the cover shape sits inside a picture [width] by [height].
     *
     * Free of [Bitmap] so the rule can be asserted on a plain JVM, which is where this
     * module's unit tests run — the decode either side of it is the framework's work and is
     * exercised on a device. Centre rather than anything cleverer: a cover's subject is in the
     * middle of it, and face detection on a book jacket finds the author's photograph on the
     * back.
     */
    fun crop(width: Int, height: Int): Crop {
        if (width <= 0 || height <= 0) return Crop(0, 0, width, height)
        val side = if (width.toFloat() / height > ASPECT_RATIO) {
            (height * ASPECT_RATIO).roundToInt() to height
        } else {
            width to (width / ASPECT_RATIO).roundToInt()
        }
        return Crop((width - side.first) / 2, (height - side.second) / 2, side.first, side.second)
    }

    /**
     * [data] centre-cropped to the cover shape and re-encoded, or null when it is not an image
     * this device can decode.
     */
    fun coverShaped(data: ByteArray): ByteArray? = runCatching {
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return null
        val box = crop(decoded.width, decoded.height)
        val cropped = Bitmap.createBitmap(decoded, box.x, box.y, box.width, box.height)
        ByteArrayOutputStream().use { out ->
            cropped.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)
            out.toByteArray()
        }
    }.getOrNull()
}
