package app.storyarc.core.format

import android.content.ContentResolver
import android.graphics.Bitmap
import android.net.Uri
import app.storyarc.core.model.Publication
import java.io.File

/**
 * Reaches a publication, wherever the library recorded it.
 *
 * A publication's identity carries a normalised path, and on Android that string
 * is either a filesystem path or a content `Uri` from a folder the user picked
 * (`local-library`). Every caller above this line would otherwise repeat the same
 * branch, so the branch lives here once and the rest of the app asks for an
 * archive or a cover without caring which kind it got.
 */
object PublicationAccess {

    /**
     * How to reach a path this module knows nothing about.
     *
     * A share's path is `smb://...`, and teaching this module to open one would point the
     * dependency the wrong way -- `core:format` would have to know about `core:smb`. Instead
     * the app registers an opener for the scheme, and the branch below stays one line.
     */
    private val remote = mutableMapOf<String, suspend (String) -> RandomAccessSource>()

    /** Registers how to open a path with the given scheme, such as `smb`. */
    fun register(scheme: String, opener: suspend (String) -> RandomAccessSource) {
        remote["$scheme://"] = opener
    }

    /** Whether a recorded path is a document from the Storage Access Framework. */
    fun isDocument(path: String): Boolean = path.startsWith("content://")

    /** Whether a recorded path belongs to a registered remote scheme. */
    fun isRemote(path: String): Boolean = remote.keys.any { path.startsWith(it) }

    /** The source behind a remote path, when one is registered. */
    suspend fun remoteSource(path: String): RandomAccessSource? =
        remote.entries.firstOrNull { path.startsWith(it.key) }?.value?.invoke(path)

    /** The publication's pages, opened. */
    suspend fun openArchive(
        resolver: ContentResolver,
        path: String,
    ): ComicArchiveReading {
        remote.entries.firstOrNull { path.startsWith(it.key) }?.let { (_, opener) ->
            // The whole point of `network-share`'s streaming requirement: the archive is
            // read where the reader is looking, not fetched first.
            return ComicArchiveOpener.open(opener(path))
        }
        return if (isDocument(path)) {
            ComicArchiveOpener.open(resolver, path.toUri())
        } else {
            ComicArchiveOpener.open(File(path))
        }
    }

    /** A PDF, opened wherever it lives. */
    fun openPdf(resolver: ContentResolver, path: String): PdfDocumentReader =
        if (isDocument(path)) {
            PdfDocumentReader(resolver, path.toUri())
        } else {
            PdfDocumentReader(File(path))
        }

    /**
     * A PDF's text layer, opened wherever the file lives, or null when there is none to open.
     *
     * Null covers two different absences on purpose, because the reader answers them the same
     * way: a device with no PDF text API (ADR-0012), and a file this app could open for
     * drawing but not for reading. Either way there is no text, and `ebook-reader` requires
     * the controls that depend on it to be absent rather than broken.
     */
    fun openPdfText(resolver: ContentResolver, path: String): PdfTextReading? =
        if (isDocument(path)) {
            PdfTextReading.open(resolver, path.toUri())
        } else {
            PdfTextReading.open(File(path))
        }

    /** The publication's cover, however it has to be produced. */
    suspend fun anyCover(
        resolver: ContentResolver,
        publication: Publication,
        path: String,
        maxPixelSize: Int,
    ): Bitmap =
        if (isDocument(path)) {
            CoverLoader.anyCover(publication, resolver, path.toUri(), maxPixelSize)
        } else {
            CoverLoader.anyCover(publication, File(path), maxPixelSize)
        }

    // androidx.core's `String.toUri` would do, and this module has no reason to
    // depend on androidx.core for one call.
    private fun String.toUri(): Uri = Uri.parse(this)
}
