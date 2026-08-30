package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The arithmetic behind a page turn, and the one part of it a screenshot cannot show.
 *
 * `comic-reader` requires a curl still settling to be catchable: "the new gesture takes
 * over from the current position without the page snapping". That is a statement about
 * where a drag *starts counting from*, so it is a statement about arithmetic — and the
 * defect it forbids was arithmetic, a settle caught at 0.8 recomputed from zero.
 *
 * iOS's `CurlTurnTests` asserts the same table, case for case.
 */
class CurlTurnTest {

    private val width = 1000f

    // Following the finger

    @Test
    fun `a drag from a flat page turns it as far as the finger went`() {
        assertEquals(0.3f, CurlTurn.progress(0f, -300f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `turn-space carries the mirroring, so a flick can be told forwards from back`() {
        assertEquals(12f, CurlTurn.forward(-12f, isRightToLeft = false), 0.001f)
        assertEquals(-12f, CurlTurn.forward(12f, isRightToLeft = false), 0.001f)
        assertEquals(12f, CurlTurn.forward(12f, isRightToLeft = true), 0.001f)
    }

    @Test
    fun `a right-to-left publication turns forward on the other direction`() {
        assertEquals(0.3f, CurlTurn.progress(0f, 300f, width, isRightToLeft = true), 0.001f)
        assertEquals(0f, CurlTurn.progress(0f, -300f, width, isRightToLeft = true), 0.001f)
    }

    // Interruption

    @Test
    fun `a drag caught mid-settle carries the page's progress as its base`() {
        // The scenario itself: the settle stands at 0.8 and the finger has barely moved.
        // Recomputed from zero this is 0.1, which is the snap the scenario forbids.
        assertEquals(0.8f, CurlTurn.progress(0.8f, -1f, width, isRightToLeft = false), 0.01f)
    }

    @Test
    fun `a drag from a caught settle is an offset from where the page stands`() {
        assertEquals(0.9f, CurlTurn.progress(0.8f, -100f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `dragging back from a caught settle unwinds the page rather than pinning it`() {
        // Clamped at zero when the drag was absolute, so the page could never be pushed
        // back: every backwards move read as "no progress" instead of "less progress".
        assertEquals(0.5f, CurlTurn.progress(0.8f, 300f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `a caught settle cannot be dragged past either end`() {
        assertEquals(1f, CurlTurn.progress(0.8f, -900f, width, isRightToLeft = false), 0.001f)
        assertEquals(0f, CurlTurn.progress(0.8f, 900f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `a width nothing has measured yet leaves the page where it stands`() {
        assertEquals(0.8f, CurlTurn.progress(0.8f, -300f, 0f, isRightToLeft = false), 0.001f)
    }

    // The release

    @Test
    fun `past halfway the turn completes`() {
        assertTrue(CurlTurn.settles(0.51f, isFlick = false))
        assertFalse(CurlTurn.settles(0.5f, isFlick = false))
    }

    @Test
    fun `a flick completes whatever the distance`() {
        assertTrue(CurlTurn.settles(0.06f, isFlick = true))
        assertFalse(CurlTurn.settles(0.06f, isFlick = false))
    }

    @Test
    fun `a flick from a page that never left flat does not turn it`() {
        assertFalse(CurlTurn.settles(0.05f, isFlick = true))
    }

    @Test
    fun `a settle caught and released where it stood still completes`() {
        // The other half of interruption: a turn caught at 0.8 and let go is past
        // halfway, so it finishes rather than springing back to a page already gone.
        assertTrue(CurlTurn.settles(0.8f, isFlick = false))
    }
}
