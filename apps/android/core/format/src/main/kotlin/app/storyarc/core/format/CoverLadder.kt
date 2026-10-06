package app.storyarc.core.format

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import app.storyarc.core.model.Publication
import java.io.ByteArrayInputStream
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
        val loose = looseCoverBytes(resolver, path) ?: return null
        return runCatching { PageDecoder.decode(loose, maxPixelSize) }.getOrNull()
    }

    /**
     * The loose cover beside [path]: a file beside a file, or a document beside a document.
     * Task 1.2 is "both" platforms and every format, and a folder the reader picks on Android
     * is a document tree, so the document case is the common one there.
     */
    private fun looseCoverBytes(resolver: ContentResolver, path: String): ByteArray? = when {
        PublicationAccess.isRemote(path) -> null
        PublicationAccess.isDocument(path) -> LooseCover.besideDocument(resolver, Uri.parse(path))
        else -> looseCover(path)?.let { runCatching { it.readBytes() }.getOrNull() }
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
     * Null for a Storage Access Framework document, which has no filesystem path to look
     * beside: [cover] reaches that case through [LooseCover.besideDocument], and an audiobook
     * folder's loose cover is copied at index time as its recorded cover. [coverFile] needs a
     * file rather than bytes, so for a single SAF document it has none to give.
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
     * The longest side a stored cover keeps. The publication page asks for 900 pixels; this
     * leaves room for a large tablet without storing a 48-megapixel photograph whole.
     */
    const val MAX_SIDE = 1600

    /** The largest picture this app reads at all. A picked file is untrusted input. */
    const val MAX_BYTES = 40 * 1024 * 1024

    /**
     * The power-of-two step [BitmapFactory] decodes at, so a picture [width] by [height] is
     * never held at full size. It stops while the longest side is still at least [MAX_SIDE],
     * so the final scale only ever shrinks.
     */
    fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        while (maxOf(width, height) / (sample * 2) >= MAX_SIDE) sample *= 2
        return sample
    }

    /** What an EXIF orientation tag asks for: a turn, then a mirror. */
    data class Orientation(val degrees: Float, val mirrored: Boolean)

    /**
     * The turn and mirror for an EXIF orientation tag. A phone writes a portrait photograph
     * as a landscape bitmap plus a tag, so a decode that ignores the tag stores it sideways.
     */
    fun orientation(tag: Int): Orientation = when (tag) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> Orientation(0f, mirrored = true)
        ExifInterface.ORIENTATION_ROTATE_180 -> Orientation(180f, mirrored = false)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> Orientation(180f, mirrored = true)
        ExifInterface.ORIENTATION_TRANSPOSE -> Orientation(90f, mirrored = true)
        ExifInterface.ORIENTATION_ROTATE_90 -> Orientation(90f, mirrored = false)
        ExifInterface.ORIENTATION_TRANSVERSE -> Orientation(270f, mirrored = true)
        ExifInterface.ORIENTATION_ROTATE_270 -> Orientation(270f, mirrored = false)
        else -> Orientation(0f, mirrored = false)
    }

    /**
     * [data] turned upright, centre-cropped to the cover shape, bounded to [MAX_SIDE] and
     * re-encoded, or null when it is too large or not an image this device can decode.
     */
    fun coverShaped(data: ByteArray): ByteArray? = runCatching {
        if (data.size > MAX_BYTES) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
        }
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return null
        val upright = upright(decoded, orientation(orientationTag(data)))
        val box = crop(upright.width, upright.height)
        val scale = minOf(1f, MAX_SIDE.toFloat() / maxOf(box.width, box.height))
        val matrix = Matrix().apply { setScale(scale, scale) }
        val cropped = Bitmap.createBitmap(upright, box.x, box.y, box.width, box.height, matrix, true)
        ByteArrayOutputStream().use { out ->
            cropped.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)
            out.toByteArray()
        }
    }.getOrNull()

    /** The picture's EXIF orientation, or normal where it carries none or cannot be read. */
    private fun orientationTag(data: ByteArray): Int = runCatching {
        ExifInterface(ByteArrayInputStream(data))
            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

    private fun upright(bitmap: Bitmap, turn: Orientation): Bitmap {
        if (turn.degrees == 0f && !turn.mirrored) return bitmap
        val matrix = Matrix().apply {
            setRotate(turn.degrees)
            if (turn.mirrored) postScale(-1f, 1f)
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
