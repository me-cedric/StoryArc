package app.storyarc.core.designsystem.navigation

import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.ui.geometry.Rect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `native-experience`, *Foldable devices*: which layout a posture gives the reader (2.1, 2.7),
 * and which fold a page and a control keep off (1.4).
 */
class WindowPostureTest {

    private fun fold(
        bounds: Rect,
        isFlat: Boolean = false,
        isVertical: Boolean = true,
        isSeparating: Boolean = true,
        isOccluding: Boolean = false,
    ) = Posture(hingeList = listOf(HingeInfo(bounds, isFlat, isVertical, isSeparating, isOccluding)))

    private val across = Rect(0f, 700f, 1400f, 700f)
    private val down = Rect(840f, 0f, 840f, 1400f)

    @Test
    fun `half open with a horizontal fold is tabletop`() {
        assertEquals(ReaderPosture.TABLETOP, ReaderPosture.of(fold(across, isVertical = false)))
    }

    @Test
    fun `half open with a vertical fold is book posture`() {
        assertEquals(ReaderPosture.BOOK, ReaderPosture.of(fold(down)))
    }

    @Test
    fun `a flat fold is the flat layout, whichever way it runs`() {
        assertEquals(ReaderPosture.FLAT, ReaderPosture.of(fold(across, isFlat = true, isVertical = false)))
        assertEquals(ReaderPosture.FLAT, ReaderPosture.of(fold(down, isFlat = true)))
    }

    /** 2.7: a device that reports no fold, no posture or no region draws the flat layout. */
    @Test
    fun `no posture and no fold are the flat layout`() {
        assertEquals(ReaderPosture.FLAT, ReaderPosture.of(null))
        assertEquals(ReaderPosture.FLAT, ReaderPosture.of(Posture()))
        assertNull(Posture().avoidedVerticalFold())
        assertNull(Posture().tabletopFold())
    }

    @Test
    fun `an occluding fold is kept off even when it does not separate`() {
        val hinge = Rect(820f, 0f, 860f, 1400f)
        assertEquals(hinge, fold(hinge, isFlat = true, isSeparating = false, isOccluding = true).avoidedVerticalFold())
    }

    @Test
    fun `a flat fold that neither separates nor occludes is not kept off`() {
        assertNull(fold(down, isFlat = true, isSeparating = false).avoidedVerticalFold())
    }

    /** A half-open Pixel Fold reports its fold as a line. The line still divides the display. */
    @Test
    fun `a fold with no width is kept off as one pixel`() {
        assertEquals(Rect(840f, 0f, 841f, 1400f), fold(down).avoidedVerticalFold())
        assertEquals(Rect(0f, 700f, 1400f, 701f), fold(across, isVertical = false).tabletopFold())
    }

    @Test
    fun `a horizontal fold is not a vertical one, and the reverse`() {
        assertNull(fold(across, isVertical = false).avoidedVerticalFold())
        assertNull(fold(down).tabletopFold())
    }
}
