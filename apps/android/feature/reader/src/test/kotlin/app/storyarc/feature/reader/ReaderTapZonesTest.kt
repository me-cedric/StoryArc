package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Where a tap turns a page, and where it does not.
 *
 * `page-transitions`: "each zone is a third of the screen's width, leaving the middle third
 * to the chrome", and with the setting off "a tap anywhere toggles the chrome, and no tap
 * turns a page".
 *
 * The zone was a quarter, which left half the screen doing nothing but toggling the chrome
 * — the gesture a reader uses least occupying the part of the screen a thumb lands on. The
 * fraction is pinned here because iOS holds the same number in
 * `ZoomablePage.edgeZoneFraction`, and a change to one that is not made to the other is a
 * reader meeting two different readers.
 */
class ReaderTapZonesTest {

    /** What [ReaderScreen]'s `handleTap` decides, as the rule alone. */
    private fun zone(x: Float, width: Float = 1200f, turns: Boolean = true): String {
        val edge = width * EDGE_ZONE_FRACTION
        return when {
            !turns -> "chrome"
            x < edge -> "back"
            x > width - edge -> "forward"
            else -> "chrome"
        }
    }

    @Test
    fun `each zone is a third of the width`() {
        assertEquals(1f / 3f, EDGE_ZONE_FRACTION)
    }

    @Test
    fun `the leading third turns back and the trailing third turns forward`() {
        assertEquals("back", zone(x = 360f))
        assertEquals("forward", zone(x = 840f))
    }

    @Test
    fun `the middle third is the chrome`() {
        assertEquals("chrome", zone(x = 600f))
        // Just inside each boundary, because a third of 1200 is 400 and 800.
        assertEquals("chrome", zone(x = 401f))
        assertEquals("chrome", zone(x = 799f))
    }

    @Test
    fun `the boundaries belong to the middle, so neither turn zone is a pixel wider`() {
        assertEquals("chrome", zone(x = 400f))
        assertEquals("chrome", zone(x = 800f))
    }

    @Test
    fun `with the zones off every tap is the chrome`() {
        assertEquals("chrome", zone(x = 360f, turns = false))
        assertEquals("chrome", zone(x = 600f, turns = false))
        assertEquals("chrome", zone(x = 840f, turns = false))
    }

    @Test
    fun `a wider screen keeps the same three shares`() {
        assertEquals("back", zone(x = 600f, width = 2400f))
        assertEquals("chrome", zone(x = 1200f, width = 2400f))
        assertEquals("forward", zone(x = 1800f, width = 2400f))
    }
}
