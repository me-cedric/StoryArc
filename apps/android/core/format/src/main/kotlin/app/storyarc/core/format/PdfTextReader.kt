package app.storyarc.core.format

import android.content.ContentResolver
import android.graphics.Point
import android.graphics.pdf.PdfRendererPreV
import android.graphics.pdf.content.PdfPageTextContent
import android.graphics.pdf.models.selection.SelectionBoundary
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.ext.SdkExtensions
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.annotation.RequiresExtension
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * A point on a page, in normalised page space.
 *
 * `0..1` across and down, origin at the page's top-left corner. Not points, and deliberately
 * so -- the reader works in the coordinates of a page it has rasterised at whatever size the
 * screen asked for, and normalised coordinates are the only ones that survive that without the
 * drawing code knowing about PDF points, page boxes or the two platforms' opposite ideas of
 * which way up a page is.
 */
data class PdfTextPoint(val x: Float, val y: Float)

/**
 * A rectangle over a page, in the same normalised space as [PdfTextPoint].
 *
 * A plain record rather than `RectF`, so the arithmetic around it is tested on the JVM.
 */
data class PdfTextRect(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
)

/**
 * A run of words in a PDF, and where they sit on the page.
 *
 * iOS's `PdfTextSelection` reports the same shape in the same space.
 */
data class PdfTextSelection(
    val locator: PdfLocator,
    /** The words themselves, as the reader will copy or quote them. */
    val text: String,
    /**
     * One rectangle per line of the run, so a selection across a line break draws as two bars
     * rather than as one block over the paragraph between them.
     */
    val rects: List<PdfTextRect>,
)

/**
 * The text inside a PDF: reading it, selecting it, and finding the same words again.
 *
 * Separate from [PdfDocumentReader], which draws pages and knows nothing about what is written
 * on them -- and separate for a reason that is not tidiness: this reader may not exist. The
 * platform's PDF text API ships in the `framework-pdf` mainline module, so a device answers for
 * itself whether it has one; see [isSupported] and ADR-0011. A reader that is null is the whole
 * of the degradation: the screen then offers no selection and no search box, exactly as it does
 * for a PDF that carries no text at all, because a control that cannot deliver what it promises
 * is worse than no control.
 *
 * An interface, and the reason is the annotation on the implementation below. `@RequiresExtension`
 * travels to every caller of the type it is on, which would put an extension check in the reader
 * screen, in the view model, and in anything either of them hands the reader to. Naming the
 * capability rather than the platform class keeps that question where it is answered -- here, in
 * [open] -- and leaves the rest of the app holding something that is either present or null.
 *
 * Not thread-safe, and not made to look like it is: the underlying document permits one open
 * page at a time, so a caller must serialise access. Close it when done.
 *
 * iOS's `PdfTextLayer` is the same set of operations on PDFKit.
 */
interface PdfTextReading : AutoCloseable {

    val pageCount: Int

    /**
     * Whether any of the pages this probes carries extractable text.
     *
     * Drives whether the reader offers selection and search at all. A scanned comic has no text
     * layer, and `ebook-reader` forbids offering a capability that is absent -- so this is
     * checked rather than assumed from the extension.
     */
    val hasTextLayer: Boolean

    /** One page's text, or null when the page has none. */
    fun text(index: Int): String?

    /**
     * What lies between two points on a page, both in normalised page space.
     *
     * Null when the drag crossed no text: the reader then shows nothing rather than an empty
     * menu, which is the honest answer to selecting a margin.
     */
    fun selection(index: Int, from: PdfTextPoint, to: PdfTextPoint): PdfTextSelection?

    /**
     * The same words again, from a stored locator.
     *
     * What paints a highlight back onto a page the reader has turned away from and come back
     * to. Null when the locator names nothing on that page any more.
     */
    fun selection(locator: PdfLocator): PdfTextSelection?

    companion object {
        /**
         * The `framework-pdf` extension that first carried text extraction, selection and
         * search. Android 15 ships it in the platform; Android 12 to 14 get it through a Google
         * Play system update, which is why this is a question about the *device* rather than
         * about the API level alone. ADR-0011.
         */
        const val PDF_TEXT_EXTENSION: Int = 13

        /** How many pages [hasTextLayer] opens before it concludes there is no text. */
        const val TEXT_PROBE_PAGES: Int = 24

        /**
         * How close two normalised points have to be before a drag counts as a press.
         *
         * The same number iOS uses, so a short drag means the same thing on both.
         */
        const val WORD_THRESHOLD: Float = 0.005f

        /** Whether this device can read the text in a PDF at all. */
        @get:ChecksSdkIntAtLeast(api = PDF_TEXT_EXTENSION, extension = Build.VERSION_CODES.S)
        val isSupported: Boolean
            get() = SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S) >=
                PDF_TEXT_EXTENSION

        /** A PDF on the filesystem, or null when this device has no PDF text API. */
        fun open(file: File): PdfTextReading? = openDescriptor {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        }

        /** A PDF inside a folder picked through the Storage Access Framework. */
        fun open(resolver: ContentResolver, uri: Uri): PdfTextReading? = openDescriptor {
            resolver.openFileDescriptor(uri, "r")
        }

        /**
         * Null rather than a throw, all the way down.
         *
         * Text is an extra this screen offers when it can. A PDF that opens for reading and
         * refuses to open a second time for its text is a PDF the reader still shows, without
         * the controls it cannot honour.
         */
        private fun openDescriptor(open: () -> ParcelFileDescriptor?): PdfTextReading? {
            if (!isSupported) return null
            val descriptor = runCatching { open() }.getOrNull() ?: return null
            val renderer = runCatching { PdfRendererPreV(descriptor) }.getOrNull()
            if (renderer == null) {
                runCatching { descriptor.close() }
                return null
            }
            return PdfTextReader(descriptor, renderer)
        }
    }
}

/**
 * [PdfTextReading] on the platform's own PDF module.
 *
 * Its own file descriptor, and therefore its own document handle. [PdfDocumentReader] holds a
 * `PdfRenderer` that permits one open page at a time, and threading text extraction through that
 * same lock would make a selection wait behind a page render. Two handles on one read-only file
 * cost a file descriptor and nothing else.
 *
 * `PdfRendererPreV` rather than `PdfRenderer` although both carry the text API from the same
 * extension: the pre-V class exists at every level this app supports once the module is there,
 * so one class answers for Android 12 through 16 and there is no second code path to keep true.
 */
@RequiresExtension(extension = Build.VERSION_CODES.S, version = 13)
internal class PdfTextReader(
    private val descriptor: ParcelFileDescriptor,
    private val renderer: PdfRendererPreV,
) : PdfTextReading {

    override val pageCount: Int get() = renderer.pageCount

    /**
     * Bounded by [PdfTextReading.TEXT_PROBE_PAGES] rather than reading the whole document.
     * Opening a page is the expensive part of a PDF, and a five-hundred-page scan would pay for
     * all of it before the first page appeared. A publication whose first two dozen pages carry
     * not one word is a scan; iOS probes the same number for the same reason.
     */
    override val hasTextLayer: Boolean by lazy {
        (0 until min(pageCount, PdfTextReading.TEXT_PROBE_PAGES)).any {
            !text(it).isNullOrBlank()
        }
    }

    /**
     * The blocks the platform reports, joined by a line break. Joined by *something*: two blocks
     * run together would let a search match across the seam between a heading and the paragraph
     * under it, and find a word that is on neither.
     */
    override fun text(index: Int): String? {
        if (index < 0 || index >= pageCount) return null
        val joined = runCatching {
            renderer.openPage(index).use { page ->
                page.textContents.joinToString("\n") { it.text }
            }
        }.getOrNull().orEmpty()
        return joined.ifBlank { null }
    }

    override fun selection(
        index: Int,
        from: PdfTextPoint,
        to: PdfTextPoint,
    ): PdfTextSelection? {
        if (index < 0 || index >= pageCount) return null
        return runCatching {
            renderer.openPage(index).use { page ->
                val width = page.width
                val height = page.height
                if (width <= 0 || height <= 0) return@use null

                // A press with no drag means "the word under my finger". The platform reads two
                // equal boundaries as exactly that, so the two cases are one call.
                val isTap = abs(from.x - to.x) < PdfTextReading.WORD_THRESHOLD &&
                    abs(from.y - to.y) < PdfTextReading.WORD_THRESHOLD
                val start = Point((from.x * width).toInt(), (from.y * height).toInt())
                val stop =
                    if (isTap) start else Point((to.x * width).toInt(), (to.y * height).toInt())

                val selected =
                    page.selectContent(SelectionBoundary(start), SelectionBoundary(stop))
                        ?: return@use null
                described(
                    locator = PdfLocator(
                        page = index,
                        start = min(selected.start.index, selected.stop.index),
                        end = max(selected.start.index, selected.stop.index),
                    ),
                    contents = selected.selectedTextContents,
                    width = width,
                    height = height,
                )
            }
        }.getOrNull()
    }

    override fun selection(locator: PdfLocator): PdfTextSelection? {
        if (locator.page < 0 || locator.page >= pageCount) return null
        if (locator.end <= locator.start) return null
        return runCatching {
            renderer.openPage(locator.page).use { page ->
                val width = page.width
                val height = page.height
                if (width <= 0 || height <= 0) return@use null
                val selected = page.selectContent(
                    SelectionBoundary(locator.start),
                    SelectionBoundary(locator.end),
                ) ?: return@use null
                described(locator, selected.selectedTextContents, width, height)
            }
        }.getOrNull()
    }

    private fun described(
        locator: PdfLocator,
        contents: List<PdfPageTextContent>,
        width: Int,
        height: Int,
    ): PdfTextSelection? {
        val text = contents.joinToString(" ") { it.text }.trim()
        if (text.isEmpty()) return null
        return PdfTextSelection(
            locator = locator,
            text = text,
            // Per line, because one rectangle around a selection that wraps would cover the
            // whole paragraph between its first word and its last.
            rects = contents
                .flatMap { it.bounds }
                .map {
                    PdfTextRect(
                        x = it.left / width,
                        y = it.top / height,
                        width = it.width() / width,
                        height = it.height() / height,
                    )
                }
                .filter { it.width > 0f && it.height > 0f },
        )
    }

    override fun close() {
        renderer.close()
        descriptor.close()
    }
}
