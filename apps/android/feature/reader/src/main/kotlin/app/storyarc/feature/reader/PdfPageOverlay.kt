package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import app.storyarc.core.format.PdfTextPoint
import app.storyarc.core.format.PdfTextRect
import app.storyarc.core.model.HighlightColour

/**
 * A mark to draw over a page: where it is, and what colour the reader chose.
 *
 * iOS's `PdfPageMark` is the same record.
 */
internal data class PdfPageMark(
    val id: String,
    /** Normalised to the page, so it survives the raster being any size. */
    val rect: PdfTextRect,
    val colour: HighlightColour,
)

/**
 * The marks and the live selection on one page, as one value.
 *
 * One value rather than two parameters on the page composable, because they change together and
 * a composable that took them separately would recompose twice for one gesture.
 *
 * iOS's `PdfPageDecoration` carries the same two lists.
 */
internal data class PdfPageDecoration(
    val marks: List<PdfPageMark> = emptyList(),
    /** Normalised to the page, like the marks. Empty when nothing is selected. */
    val selection: List<PdfTextRect> = emptyList(),
) {
    val isEmpty: Boolean get() = marks.isEmpty() && selection.isEmpty()
}

/**
 * What is painted over a PDF page, and the arithmetic that puts it in the right place.
 *
 * The reader draws a page as a raster at whatever size the screen asked for, and everything the
 * text layer reports is normalised to the page instead -- `0..1` across and down. This is the
 * one place the two meet.
 *
 * Free functions over [PageBounds] so the whole conversion is exercised on the JVM, without a
 * device: the same reason [PageZoom] is a value rather than state inside a composable.
 *
 * iOS's `PdfPageOverlay` maps the same two spaces.
 */

/**
 * Where the page's artwork actually sits inside the area fitting it.
 *
 * The page is drawn fit-to-screen, so a portrait page in a landscape area has bars either side
 * and a point in the *area* is not a point on the *page*. Everything below converts through
 * this rectangle.
 */
internal fun pageRect(page: PageBounds): Rect {
    if (page.fittedWidth <= 0f || page.fittedHeight <= 0f) return Rect.Zero
    return Rect(
        offset = Offset(
            (page.area.width - page.fittedWidth) / 2f,
            (page.area.height - page.fittedHeight) / 2f,
        ),
        size = Size(page.fittedWidth, page.fittedHeight),
    )
}

/**
 * A point in the fitting area, as a fraction of the page under it.
 *
 * Clamped, because a drag that leaves the artwork still means "the edge of the page" rather than
 * a coordinate off it -- a reader sweeping past the last word has selected to the end of the
 * line, not to nowhere.
 */
internal fun normalisedPoint(point: Offset, page: PageBounds): PdfTextPoint {
    val rect = pageRect(page)
    if (rect.width <= 0f || rect.height <= 0f) return PdfTextPoint(0f, 0f)
    return PdfTextPoint(
        x = ((point.x - rect.left) / rect.width).coerceIn(0f, 1f),
        y = ((point.y - rect.top) / rect.height).coerceIn(0f, 1f),
    )
}

/** A normalised rectangle, back in the coordinates of the fitting area. */
internal fun viewRect(normalised: PdfTextRect, page: PageBounds): Rect {
    val rect = pageRect(page)
    return Rect(
        offset = Offset(
            rect.left + normalised.x * rect.width,
            rect.top + normalised.y * rect.height,
        ),
        size = Size(normalised.width * rect.width, normalised.height * rect.height),
    )
}
