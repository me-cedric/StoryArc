package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
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

    @Test
    fun `a fitted page has nowhere to pan to`() {
        val zoom = PageZoom().pinched(centre, zoomChange = 1f, pan = Offset(300f, 300f), screen)
        assertEquals(PageZoom.FIT, zoom.scale, 0.001f)
        assertEquals(Offset.Zero, zoom.offset)
        assertFalse(zoom.isMagnified)
    }

    @Test
    fun `pinching at the centre magnifies without shifting`() {
        val zoom = PageZoom().pinched(centre, zoomChange = 2f, pan = Offset.Zero, screen)
        assertEquals(2f, zoom.scale, 0.001f)
        assertEquals(Offset.Zero, zoom.offset)
    }

    @Test
    fun `pinching off-centre keeps the point under the fingers still`() {
        val point = Offset(250f, 500f)
        val zoom = PageZoom().pinched(point, zoomChange = 2f, pan = Offset.Zero, screen)

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
            PageZoom().pinched(centre, zoomChange = 0.1f, pan = Offset.Zero, screen).scale,
            0.001f,
        )
        assertEquals(
            PageZoom.MAXIMUM,
            PageZoom().pinched(centre, zoomChange = 100f, pan = Offset.Zero, screen).scale,
            0.001f,
        )
    }

    @Test
    fun `panning cannot drag the page off the screen`() {
        val magnified = PageZoom().pinched(centre, zoomChange = 2f, pan = Offset.Zero, screen)
        val dragged = magnified.pinched(centre, zoomChange = 1f, pan = Offset(9_000f, 9_000f), screen)

        // At 2x the page is twice the screen, so half of it can move past either
        // edge — no further.
        assertEquals(screen.width / 2f, dragged.offset.x, 0.001f)
        assertEquals(screen.height / 2f, dragged.offset.y, 0.001f)
    }

    @Test
    fun `a double tap magnifies about the tapped point`() {
        val point = Offset(250f, 500f)
        val zoom = PageZoom().doubleTapped(point, screen)

        assertEquals(PageZoom.DOUBLE_TAP, zoom.scale, 0.001f)
        assertTrue(zoom.isMagnified)
        // The tapped content moves towards the middle of the screen rather than
        // staying at the edge.
        val landed = centre + (point - centre) * zoom.scale + zoom.offset
        assertTrue("expected $landed to be nearer the centre", (landed - centre).getDistance() < 250f)
    }

    @Test
    fun `a second double tap returns to fit`() {
        val magnified = PageZoom().doubleTapped(Offset(250f, 500f), screen)
        val fitted = magnified.doubleTapped(Offset(250f, 500f), screen)

        assertEquals(PageZoom.FIT, fitted.scale, 0.001f)
        assertEquals(Offset.Zero, fitted.offset)
    }
}
