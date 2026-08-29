package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.PageFit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The arithmetic behind pinch and double-tap.
 *
 * `comic-reader` asks for zoom "about the pinch centre" and panning "within
 * bounds". Both are sign-sensitive: get one wrong and the page leaves the screen,
 * which is exactly the kind of thing a screenshot of a solid-colour fixture will
 * not catch.
 */
class PageZoomTest {

    private val screen = IntSize(1000, 2000)
    private val centre = Offset(500f, 1000f)

    /** A page that exactly fills the screen: no letterboxing to reason about. */
    private val page = PageBounds.of(image = IntSize(1000, 2000), area = screen)

    /**
     * A tall page on a wide screen, so the artwork is narrower than the viewport.
     * This is the case the bounds used to get wrong.
     */
    private val letterboxed = PageBounds.of(image = IntSize(500, 2000), area = screen)

    @Test
    fun `a fitted page has nowhere to pan to`() {
        val zoom = PageZoom().pinched(centre, zoomChange = 1f, pan = Offset(300f, 300f), page)
        assertEquals(PageZoom.FIT, zoom.scale, 0.001f)
        assertEquals(Offset.Zero, zoom.offset)
        assertFalse(zoom.isMagnified)
    }

    @Test
    fun `pinching at the centre magnifies without shifting`() {
        val zoom = PageZoom().pinched(centre, zoomChange = 2f, pan = Offset.Zero, page)
        assertEquals(2f, zoom.scale, 0.001f)
        assertEquals(Offset.Zero, zoom.offset)
    }

    @Test
    fun `pinching off-centre keeps the point under the fingers still`() {
        val point = Offset(250f, 500f)
        val zoom = PageZoom().pinched(point, zoomChange = 2f, pan = Offset.Zero, page)

        // Where the content that was under `point` ends up: the page is scaled
        // about its own centre, then translated.
        val landed = centre + (point - centre) * zoom.scale + zoom.offset
        assertEquals(point.x, landed.x, 0.5f)
        assertEquals(point.y, landed.y, 0.5f)
    }

    @Test
    fun `zoom never goes below fit or above the ceiling`() {
        assertEquals(
            PageZoom.FIT,
            PageZoom().pinched(centre, zoomChange = 0.1f, pan = Offset.Zero, page).scale,
            0.001f,
        )
        assertEquals(
            PageZoom.MAXIMUM,
            PageZoom().pinched(centre, zoomChange = 100f, pan = Offset.Zero, page).scale,
            0.001f,
        )
    }

    @Test
    fun `panning cannot drag the page off the screen`() {
        val magnified = PageZoom().pinched(centre, zoomChange = 2f, pan = Offset.Zero, page)
        val dragged = magnified.pinched(centre, zoomChange = 1f, pan = Offset(9_000f, 9_000f), page)

        // At 2x the page is twice the screen, so half of it can move past either
        // edge — no further.
        assertEquals(screen.width / 2f, dragged.offset.x, 0.001f)
        assertEquals(screen.height / 2f, dragged.offset.y, 0.001f)
    }

    @Test
    fun `a letterboxed page cannot be dragged past its own artwork`() {
        // 500 x 2000 in a 1000 x 2000 screen fits to 500 wide, so at 2x the artwork
        // is exactly the screen's width and has no horizontal slack at all. Bounds
        // taken from the viewport instead would have allowed 500 points of drag,
        // which walks the page off the edge.
        val magnified = PageZoom().pinched(centre, 2f, Offset.Zero, letterboxed)
        val dragged = magnified.pinched(centre, 1f, Offset(9_000f, 9_000f), letterboxed)

        assertEquals(0f, dragged.offset.x, 0.001f)
        assertEquals(1000f, dragged.offset.y, 0.001f)
    }

    @Test
    fun `fit-to-width opens at the top of the page, magnified`() {
        // `comic-reader`: the next page "returns to the top of the page in reading
        // order". A page opened in the middle of its own first panel reads as a
        // scroll position left over from somewhere else.
        val zoom = PageZoom.fitting(PageFit.WIDTH, letterboxed)

        assertEquals(2f, zoom.scale, 0.001f)
        assertEquals(0f, zoom.offset.x, 0.001f)
        assertEquals(letterboxed.slack(zoom.scale).y, zoom.offset.y, 0.001f)
    }

    @Test
    fun `fit-to-screen opens where it always did`() {
        val zoom = PageZoom.fitting(PageFit.SCREEN, letterboxed)
        assertEquals(PageZoom.FIT, zoom.scale, 0.001f)
        assertEquals(Offset.Zero, zoom.offset)
    }

    @Test
    fun `a fit taken before the page was measured carries nothing forward`() {
        // The iOS reader had a defect here worth pinning on this side too. There, a fit
        // computed against a viewport of zero was *recorded as applied*, so nothing ever
        // retried it and the page stayed at its own pixel size in a corner. Compose has no
        // such record — the zoom is keyed on the size `onSizeChanged` reports, which is
        // only ever a size the layout really has — but that only helps if the fit taken
        // before the first measurement is harmless. This is what makes it harmless.
        val unmeasured = PageBounds.of(image = IntSize(500, 2000), area = IntSize.Zero)
        val early = PageZoom.fitting(PageFit.WIDTH, unmeasured)

        assertEquals(PageZoom.FIT, early.scale, 0.001f)
        assertEquals(Offset.Zero, early.offset)
        assertFalse(early.isMagnified)

        // And the fit taken once there is a size is the real one, unaffected by it.
        assertEquals(2f, PageZoom.fitting(PageFit.WIDTH, letterboxed).scale, 0.001f)
    }

    @Test
    fun `a page with no pixels is fitted to nothing rather than to a division by zero`() {
        val undecoded = PageBounds.of(image = IntSize.Zero, area = screen)

        assertEquals(0f, undecoded.fittedWidth, 0.001f)
        assertEquals(Offset.Zero, undecoded.slack(PageZoom.MAXIMUM))
        assertEquals(PageZoom.FIT, PageZoom.fitting(PageFit.ORIGINAL, undecoded).scale, 0.001f)
    }

    @Test
    fun `a double tap magnifies about the tapped point`() {
        val point = Offset(250f, 500f)
        val zoom = PageZoom().doubleTapped(point, page)

        assertEquals(PageZoom.DOUBLE_TAP, zoom.scale, 0.001f)
        assertTrue(zoom.isMagnified)
        // The tapped content moves towards the middle of the screen rather than
        // staying at the edge.
        val landed = centre + (point - centre) * zoom.scale + zoom.offset
        assertTrue("expected $landed to be nearer the centre", (landed - centre).getDistance() < 250f)
    }

    @Test
    fun `a second double tap returns to fit`() {
        val magnified = PageZoom().doubleTapped(Offset(250f, 500f), page)
        val fitted = magnified.doubleTapped(Offset(250f, 500f), page)

        assertEquals(PageZoom.FIT, fitted.scale, 0.001f)
        assertEquals(Offset.Zero, fitted.offset)
    }
}
