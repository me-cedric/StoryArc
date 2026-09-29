package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Space, Page Up/Down and the volume keys turn in reading order, not display order.
 *
 * `comic-reader`: these keys mean "the next page to read". In left-to-right that is the
 * same as "the next position on screen", but under right-to-left the display order is
 * reversed and the two point opposite ways, so the step must flip.
 */
class ReadingOrderStepTest {
    @Test
    fun `left-to-right keeps the step`() {
        assertEquals(1, readingOrderStep(1, isRightToLeft = false))
        assertEquals(-1, readingOrderStep(-1, isRightToLeft = false))
    }

    @Test
    fun `right-to-left flips the step, so next still reads forward`() {
        assertEquals(-1, readingOrderStep(1, isRightToLeft = true))
        assertEquals(1, readingOrderStep(-1, isRightToLeft = true))
    }

    // `adjacentDisplayIndex`: what a curl's beneath and previous sheets are computed from.
    // `page-transitions` 8.14: a right-to-left curl turned to the previous page on the
    // next-page gesture because these were read straight off the display index.

    @Test
    fun `left-to-right steps the display index directly`() {
        assertEquals(2, adjacentDisplayIndex(from = 1, steps = 1, slotCount = 5, isRightToLeft = false))
        assertEquals(0, adjacentDisplayIndex(from = 1, steps = -1, slotCount = 5, isRightToLeft = false))
    }

    @Test
    fun `right-to-left steps the display index backwards for a reading-order forward step`() {
        // The bug this guards: handing a right-to-left curl `from + 1` as its forward
        // reveal, which is the *previous* page once the display order is reversed.
        assertEquals(0, adjacentDisplayIndex(from = 1, steps = 1, slotCount = 5, isRightToLeft = true))
        assertEquals(2, adjacentDisplayIndex(from = 1, steps = -1, slotCount = 5, isRightToLeft = true))
    }

    @Test
    fun `a step past either end of the publication is null`() {
        assertEquals(null, adjacentDisplayIndex(from = 4, steps = 1, slotCount = 5, isRightToLeft = false))
        assertEquals(null, adjacentDisplayIndex(from = 0, steps = -1, slotCount = 5, isRightToLeft = false))
        assertEquals(null, adjacentDisplayIndex(from = 0, steps = 1, slotCount = 5, isRightToLeft = true))
    }
}
