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

    /** Whether a recorded path is a document from the Storage Access Framework. */
    fun isDocument(path: String): Boolean = path.startsWith("content://")

    /** The publication's pages, opened. */
    suspend fun openArchive(
        resolver: ContentResolver,
        path: String,
    ): ComicArchiveReading =
        if (isDocument(path)) {
            ComicArchiveOpener.open(resolver, path.toUri())
        } else {
            ComicArchiveOpener.open(File(path))
        }

    /** A PDF, opened wherever it lives. */
    fun openPdf(resolver: ContentResolver, path: String): PdfDocumentReader =
        if (isDocument(path)) {
            PdfDocumentReader(resolver, path.toUri())
        } else {
            PdfDocumentReader(File(path))
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
