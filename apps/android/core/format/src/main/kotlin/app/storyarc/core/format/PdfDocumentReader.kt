package app.storyarc.core.format

import android.graphics.Bitmap
import android.graphics.Color
import android.content.ContentResolver
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File

sealed class PdfException(message: String) : Exception(message) {
    /** `PdfRenderer` refused the file. Encrypted, truncated, or not a PDF. */
    class Unreadable(message: String = "pdf unreadable") : PdfException(message)

    class PageOutOfRange(index: Int) : PdfException("no page at index $index")
}

/**
 * Reads a PDF as a paged publication.
 *
 * The page: count, size in points, and rendering on demand. `ebook-reader`
 * requires a several-hundred-megabyte PDF opened from a remote source to render
 * pages as they are needed, which is why no page is rasterised until it is asked
 * for.
 *
 * What is written on the page is next door, in [PdfTextReader]. [PdfRenderer]
 * itself gained text extraction, selection and search in the `framework-pdf`
 * mainline module, but only from extension 13 -- so the text half is a reader a
 * device may not have at all, and it is kept apart from the one that always
 * exists. ADR-0012 records that.
 *
 * There is no `hasTextLayer` here on purpose: this type cannot answer the
 * question, and a property that always returned false would invite a caller to
 * treat it as a real answer. [PdfTextReader.hasTextLayer] is the answer.
 *
 * Not thread-safe, and not made to look like it is: [PdfRenderer] permits one
 * open page at a time, so a caller must serialise access. Close it when done.
 */
class PdfDocumentReader private constructor(
    private val descriptor: ParcelFileDescriptor,
) : AutoCloseable {

    constructor(file: File) : this(descriptorFor(file))

    /** A PDF inside a folder picked through the Storage Access Framework. */
    constructor(resolver: ContentResolver, uri: Uri) : this(descriptorFor(resolver, uri))

    private val renderer: PdfRenderer =
        try {
            PdfRenderer(descriptor)
        } catch (cause: Exception) {
            descriptor.close()
            throw PdfException.Unreadable(cause.message ?: "not a pdf")
        }

    companion object {
        private fun descriptorFor(file: File): ParcelFileDescriptor =
            try {
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            } catch (cause: Exception) {
                throw PdfException.Unreadable(cause.message ?: "cannot open file")
            }

        private fun descriptorFor(resolver: ContentResolver, uri: Uri): ParcelFileDescriptor =
            try {
                resolver.openFileDescriptor(uri, "r")
                    ?: throw PdfException.Unreadable("no file descriptor for $uri")
            } catch (cause: PdfException) {
                throw cause
            } catch (cause: Exception) {
                throw PdfException.Unreadable(cause.message ?: "cannot open document")
            }
    }

    val pageCount: Int get() = renderer.pageCount

    /**
     * A page's size in PDF points, which is what fit and zoom are computed from.
     *
     * Points rather than pixels on purpose: the same page must present at the
     * same aspect ratio and fit on both platforms, and pixels depend on the
     * screen while points do not.
     */
    fun sizePoints(index: Int): PageSize = openPage(index).use { page ->
        PageSize(page.width, page.height)
    }

    /**
     * Renders one page, bounded on its longest edge.
     *
     * The bound is the same contract [PageDecoder.decode] offers for images, so a
     * PDF page and a comic page cost the same to show. Never upscales: asking for
     * more than the page has returns it at its natural size.
     */
    fun render(index: Int, maxPixelSize: Int? = null): Bitmap = openPage(index).use { page ->
        if (page.width <= 0 || page.height <= 0) throw PdfException.Unreadable("page has no size")
        val target =
            if (maxPixelSize == null) {
                PageSize(page.width, page.height)
            } else {
                PageDecoder.targetSize(page.width, page.height, maxPixelSize)
            }
        val bitmap = Bitmap.createBitmap(target.width, target.height, Bitmap.Config.ARGB_8888)
        // A PDF page has no background of its own, and PdfRenderer draws onto
        // whatever is already there. Without this the page renders dark text onto
        // transparency and reads as black on black.
        bitmap.eraseColor(Color.WHITE)
        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        bitmap
    }

    private fun openPage(index: Int): PdfRenderer.Page {
        if (index < 0 || index >= renderer.pageCount) throw PdfException.PageOutOfRange(index)
        return renderer.openPage(index)
    }

    override fun close() {
        renderer.close()
        descriptor.close()
    }
}
