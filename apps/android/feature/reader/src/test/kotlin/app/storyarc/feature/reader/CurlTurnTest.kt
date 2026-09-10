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
        assertEquals(-1f, CurlTurn.progress(0.8f, 1900f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `a drag backwards from flat turns the page behind, which is a negative progress`() {
        // The reader's report: "page curl only seems to work in one direction, sliding to
        // the previous page does nothing". It did nothing because the range was clamped at
        // zero, so a backwards drag from a flat page was arithmetically indistinguishable
        // from no drag at all.
        assertEquals(-0.3f, CurlTurn.progress(0f, 300f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `the range clamps at a whole turn in each direction`() {
        assertEquals(1f, CurlTurn.progress(0f, -4000f, width, isRightToLeft = false), 0.001f)
        assertEquals(-1f, CurlTurn.progress(0f, 4000f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `a right-to-left publication mirrors both signs`() {
        assertEquals(0.3f, CurlTurn.progress(0f, 300f, width, isRightToLeft = true), 0.001f)
        assertEquals(-0.3f, CurlTurn.progress(0f, -300f, width, isRightToLeft = true), 0.001f)
    }

    @Test
    fun `with no page behind it the negative range collapses to nothing`() {
        // The first page. `page-transitions`: a backwards drag there "moves nothing", and
        // the guard is here rather than in the shader because the shader would have no
        // sheet to turn and would draw the page beneath at rest.
        assertEquals(
            0f,
            CurlTurn.progress(0f, 300f, width, isRightToLeft = false, canTurnBack = false),
            0.001f,
        )
        // And a page that is part-way through a forward turn still unwinds to flat.
        assertEquals(
            0f,
            CurlTurn.progress(0.4f, 400f, width, isRightToLeft = false, canTurnBack = false),
            0.001f,
        )
    }

    @Test
    fun `with no page beneath the forward range is left alone, because the end screen is a turn`() {
        // `comic-reader` reaches an end screen by turning past the last page, so the last
        // page's forward turn is a turn and not a nothing. Stated as a test because the
        // symmetry is tempting and would take the end screen away.
        assertEquals(1f, CurlTurn.progress(0f, -1200f, width, isRightToLeft = false), 0.001f)
    }

    @Test
    fun `a backwards flick completes a backwards turn`() {
        assertTrue(CurlTurn.flicks(lastStep = 40f, progress = -0.1f, isRightToLeft = false))
        assertTrue(CurlTurn.settles(-0.06f, isFlick = true))
    }

    @Test
    fun `a flick has to agree with where the page is already going`() {
        // A fast finger dragging the page back at a forward progress has said it does not
        // want the turn. An unsigned flick completed it anyway.
        assertFalse(CurlTurn.flicks(lastStep = 40f, progress = 0.3f, isRightToLeft = false))
        assertFalse(CurlTurn.flicks(lastStep = -40f, progress = -0.3f, isRightToLeft = false))
        assertTrue(CurlTurn.flicks(lastStep = -40f, progress = 0.3f, isRightToLeft = false))
    }

    @Test
    fun `past halfway backwards the turn completes too`() {
        assertTrue(CurlTurn.settles(-0.51f, isFlick = false))
        assertFalse(CurlTurn.settles(-0.5f, isFlick = false))
    }

    @Test
    fun `a negative progress turns the page behind over the page in view`() {
        // The mapping the shader is given: a backwards turn is the forward projection run
        // on the previous page, at one minus the distance dragged. At a whole turn back the
        // previous page is flat and fully in view; at nothing dragged it is fully folded
        // away and the current page is what shows.
        val nearlyBack = CurlTurn.sheets(-0.9f, page = "current", beneath = "next", previous = "previous")

        assertEquals("previous", nearlyBack.turning)
        assertEquals("current", nearlyBack.under)
        assertEquals(0.1f, nearlyBack.progress, 0.001f)
    }

    @Test
    fun `a positive progress turns the page in view over the one beneath it`() {
        val forwards = CurlTurn.sheets(0.3f, page = "current", beneath = "next", previous = "previous")

        assertEquals("current", forwards.turning)
        assertEquals("next", forwards.under)
        assertEquals(0.3f, forwards.progress, 0.001f)
    }

    @Test
    fun `a flat page is the page in view, whichever way the last drag went`() {
        val flat = CurlTurn.sheets(0f, page = "current", beneath = "next", previous = "previous")

        assertEquals("current", flat.turning)
        assertEquals(0f, flat.progress, 0.001f)
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
