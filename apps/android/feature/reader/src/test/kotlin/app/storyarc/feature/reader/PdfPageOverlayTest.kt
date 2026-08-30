package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.format.PdfTextRect
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Mirrors iOS's `PdfPageOverlayTests`, assertion for assertion.
 *
 * The conversion between a page and the area fitting it. Arithmetic over values, so it is
 * asserted on the JVM rather than on a device -- which is the whole reason these are free
 * functions rather than code inside a composable.
 *
 * The outline half of the iOS suite has no mirror here, and is not missing: this platform's PDF
 * API exposes no document outline. ADR-0012.
 */
class PdfPageOverlayTest {

    /** A portrait page in a landscape area: bars either side, and none above or below. */
    private val page = PageBounds.of(IntSize(200, 300), IntSize(400, 300))

    @Test
    fun `the page sits centred inside the area that is fitting it`() {
        val rect = pageRect(page)
        assertEquals(100f, rect.left, 0.001f)
        assertEquals(0f, rect.top, 0.001f)
        assertEquals(200f, rect.width, 0.001f)
        assertEquals(300f, rect.height, 0.001f)
    }

    @Test
    fun `an area with no size has no page in it`() {
        assertEquals(0f, pageRect(PageBounds.of(IntSize(200, 300), IntSize.Zero)).width, 0.001f)
        assertEquals(0f, pageRect(PageBounds.of(IntSize.Zero, IntSize(400, 300))).width, 0.001f)
    }

    @Test
    fun `a point on the page is reported as the fraction of it`() {
        // The middle of the artwork, which is not the middle of the area's left half.
        val middle = normalisedPoint(Offset(200f, 150f), page)
        assertEquals(0.5f, middle.x, 0.001f)
        assertEquals(0.5f, middle.y, 0.001f)
    }

    @Test
    fun `a point in the bar beside the page is clamped to the page's edge`() {
        assertEquals(0f, normalisedPoint(Offset(0f, 150f), page).x, 0.001f)
        assertEquals(1f, normalisedPoint(Offset(400f, 150f), page).x, 0.001f)
    }

    @Test
    fun `a normalised rectangle lands back where it came from`() {
        val drawn = viewRect(PdfTextRect(0.25f, 0.5f, 0.5f, 0.1f), page)
        assertEquals(150f, drawn.left, 0.001f)
        assertEquals(150f, drawn.top, 0.001f)
        assertEquals(100f, drawn.width, 0.001f)
        assertEquals(30f, drawn.height, 0.001f)
    }

    @Test
    fun `a finger on a zoomed page is unprojected back onto the words`() {
        // At fit scale with nothing panned the two spaces are the same.
        val fitted = PageZoom()
        assertEquals(Offset(200f, 150f), fitted.unprojected(Offset(200f, 150f), page))

        // Magnified about the centre: a point on the screen is nearer the centre on the page.
        val zoomed = PageZoom(scale = 2f)
        assertEquals(Offset(300f, 150f), zoomed.unprojected(Offset(400f, 150f), page))

        // And panned: the translation comes off before the scale is undone.
        val panned = PageZoom(scale = 2f, offset = Offset(50f, 0f))
        assertEquals(Offset(275f, 150f), panned.unprojected(Offset(400f, 150f), page))
    }
}
