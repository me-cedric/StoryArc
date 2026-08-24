package app.storyarc.core.format

import android.graphics.Bitmap
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import java.io.File

sealed class CoverException(message: String) : Exception(message) {
    /**
     * The publication has no cover to load — no pages, or a format that does not
     * carry one.
     */
    class NoCover : CoverException("no cover")

    /** The cover is named and could not be read. */
    class Unreadable : CoverException("cover unreadable")
}

/**
 * Produces a publication's cover image, on demand.
 *
 * Separate from indexing on purpose. `publication-formats` requires that a scan of
 * 10,000 publications show its first screen within three seconds, and that "covers
 * are extracted lazily as rows approach the viewport, not all at once during the
 * scan". So [PublicationIndexer] records *where* the cover is and this reads it
 * only when a row is about to be seen.
 *
 * Every load is bounded by the size it will be drawn at. A grid thumbnail is a
 * couple of hundred pixels across; decoding a 2000x3000 page to fill one costs
 * 24 MB of pixels for something shown at a fortieth of that.
 */
object CoverLoader {

    /**
     * The cover's raw bytes, undecoded.
     *
     * For a caller that wants to cache the bytes rather than the pixels — a
     * thumbnail store, say, which wants one copy at one size rather than whatever
     * the last viewport asked for.
     *
     * This is the whole of the cover path that runs on a plain JVM, which is why it
     * is separate from decoding: it is unit-testable, and [Bitmap] is not.
     */
    suspend fun coverData(publication: Publication, file: File): ByteArray =
        when (publication.format) {
            // A PDF page is rendered rather than extracted, so there is nothing to
            // read out. `renderedCover` produces one instead.
            PublicationFormat.PDF -> throw CoverException.NoCover()

            PublicationFormat.EPUB -> {
                val path = publication.coverPath ?: throw CoverException.NoCover()
                val reader = runCatching { EpubReader.open(FileSource(file)) }.getOrNull()
                    ?: throw CoverException.Unreadable()
                runCatching { reader.data(path) }.getOrNull() ?: throw CoverException.Unreadable()
            }

            else -> {
                val path = publication.coverPath ?: throw CoverException.NoCover()
                val archive = runCatching { ComicArchiveOpener.open(file) }.getOrNull()
                    ?: throw CoverException.Unreadable()
                archive.use {
                    val page = it.pages.firstOrNull { entry -> entry.path == path }
                        ?: it.coverPage
                        ?: throw CoverException.NoCover()
                    runCatching { it.data(page) }.getOrNull()
                        ?: throw CoverException.Unreadable()
                }
            }
        }

    /**
     * The cover of a publication, decoded and bounded on its longest edge.
     *
     * [maxPixelSize] is the size it will be *drawn* at, in pixels. Passing the
     * display's need rather than nothing is the whole point of the type.
     */
    suspend fun cover(publication: Publication, file: File, maxPixelSize: Int): Bitmap =
        runCatching { PageDecoder.decode(coverData(publication, file), maxPixelSize) }
            .getOrElse { cause ->
                if (cause is CoverException) throw cause else throw CoverException.Unreadable()
            }

    /**
     * A cover for a format whose pages are drawn rather than stored.
     *
     * PDF only. Kept separate because the two have genuinely different costs — one
     * reads bytes, the other rasterises a page — and a caller batching thumbnails
     * will want to know which it is doing.
     */
    fun renderedCover(file: File, maxPixelSize: Int): Bitmap =
        runCatching {
            PdfDocumentReader(file).use { reader ->
                if (reader.pageCount <= 0) throw CoverException.NoCover()
                reader.render(0, maxPixelSize)
            }
        }.getOrElse { cause ->
            if (cause is CoverException) throw cause else throw CoverException.Unreadable()
        }

    /**
     * The cover of any publication, whichever way it has to be produced.
     *
     * The one call a grid cell should make. It hides the difference between a
     * stored cover and a rendered one, which is not a distinction a list of rows
     * should have to care about.
     */
    suspend fun anyCover(publication: Publication, file: File, maxPixelSize: Int): Bitmap =
        if (publication.format == PublicationFormat.PDF) {
            renderedCover(file, maxPixelSize)
        } else {
            cover(publication, file, maxPixelSize)
        }
}
