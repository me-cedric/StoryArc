package app.storyarc.core.designsystem.back

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The shape of the back gesture.
 *
 * `native-experience` asks for predictive back, and the part of it a reader actually
 * sees is this transform. A test that only proved the callback fired would prove the
 * app still goes back — which it did before any of this existed.
 */
class BackPreviewTest {
    @Test
    fun `a gesture that has not moved leaves the screen alone`() {
        val preview = backPreview(progress = 0f, fromLeftEdge = true)

        assertEquals(1f, preview.scale, TOLERANCE)
        assertEquals(0f, preview.cornerRadius, TOLERANCE)
        assertEquals(BackPreview.settled, preview)
    }

    @Test
    fun `a committed gesture shrinks the screen to Android's own ninety per cent`() {
        val preview = backPreview(progress = 1f, fromLeftEdge = true)

        assertEquals(0.9f, preview.scale, TOLERANCE)
        assertEquals(BackPreview.CORNER, preview.cornerRadius, TOLERANCE)
    }

    @Test
    fun `the screen retreats from the edge the finger came from`() {
        // Pinned to the far edge, so the gap opens under the finger rather than
        // opposite it. Swapping these two is the bug this test exists to catch.
        assertEquals(1f, backPreview(0.5f, fromLeftEdge = true).originX, TOLERANCE)
        assertEquals(0f, backPreview(0.5f, fromLeftEdge = false).originX, TOLERANCE)
    }

    @Test
    fun `progress outside its documented range cannot turn the screen inside out`() {
        assertEquals(1f, backPreview(-0.5f, fromLeftEdge = true).scale, TOLERANCE)
        assertEquals(0.9f, backPreview(2f, fromLeftEdge = true).scale, TOLERANCE)
        assertTrue(backPreview(2f, fromLeftEdge = true).cornerRadius <= BackPreview.CORNER)
    }

    @Test
    fun `the shrink grows with the gesture rather than jumping at the end`() {
        val early = backPreview(0.25f, fromLeftEdge = true)
        val late = backPreview(0.75f, fromLeftEdge = true)

        assertTrue(early.scale > late.scale)
        assertTrue(early.cornerRadius < late.cornerRadius)
    }

    @Test
    fun `a screen at rest pays for no clip`() {
        // The clip exists to round the corners of a shrinking screen. A screen that is not
        // shrinking has square corners and nothing to hide, and a layer it does not need
        // would be paid for on every frame of every scroll behind it.
        assertFalse(backPreview(0f, fromLeftEdge = true).needsClip)
        assertFalse(BackPreview.settled.needsClip)
    }

    @Test
    fun `a screen that has begun to leave is clipped to its corners`() {
        assertTrue(backPreview(0.01f, fromLeftEdge = true).needsClip)
        assertTrue(backPreview(0.5f, fromLeftEdge = false).needsClip)
        assertTrue(backPreview(1f, fromLeftEdge = true).needsClip)
    }

    private companion object {
        const val TOLERANCE = 0.0001f
    }
}
