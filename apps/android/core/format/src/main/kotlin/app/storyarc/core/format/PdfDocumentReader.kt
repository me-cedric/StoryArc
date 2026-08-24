package app.storyarc.core.format

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
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
 * PDF is the one format where the two platforms are deliberately not symmetric.
 * `ebook-reader` makes text-layer features iOS-only in 1.0, because Android
 * offers no PDF text API that is also a renderer — [PdfRenderer] draws pages and
 * exposes nothing else. So this type has no `text`, `search` or `outline`, and
 * iOS's `PdfDocumentReader` does: not missing work, a specified difference.
 *
 * The consequence for the UI is in the spec too. Because the capability is absent
 * rather than failing, text-dependent controls are **hidden** on Android, never
 * shown disabled — nothing may suggest that search is available and broken. There
 * is no `hasTextLayer` here on purpose: the platform cannot answer the question,
 * and a property that always returned `false` would invite a caller to treat it
 * as a real answer.
 *
 * What *is* symmetric is the page: count, size in points, and rendering on
 * demand. `ebook-reader` requires a several-hundred-megabyte PDF opened from a
 * remote source to render pages as they are needed, which is why no page is
 * rasterised until it is asked for.
 *
 * Not thread-safe, and not made to look like it is: [PdfRenderer] permits one
 * open page at a time, so a caller must serialise access. Close it when done.
 */
class PdfDocumentReader(file: File) : AutoCloseable {
    private val descriptor: ParcelFileDescriptor =
        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        } catch (cause: Exception) {
            throw PdfException.Unreadable(cause.message ?: "cannot open file")
        }

    private val renderer: PdfRenderer =
        try {
            PdfRenderer(descriptor)
        } catch (cause: Exception) {
            descriptor.close()
            throw PdfException.Unreadable(cause.message ?: "not a pdf")
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
