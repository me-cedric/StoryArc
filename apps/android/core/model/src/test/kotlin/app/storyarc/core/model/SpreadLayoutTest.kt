package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which pages share a screen in landscape.
 *
 * `comic-reader` states three rules — pair consecutive portrait pages, show a wide page
 * alone, and let the reader shift the pairing by one — and every one of them is
 * arithmetic. iOS's `SpreadLayoutTests` asserts the same table.
 */
class SpreadLayoutTest {
    private fun shape(layout: SpreadLayout) = layout.slots.map { it.pages }

    @Test
    fun `portrait shows every page on its own`() {
        assertEquals(listOf(listOf(0), listOf(1), listOf(2), listOf(3)), shape(SpreadLayout.single(4)))
    }

    @Test
    fun `a publication with no pages has no slots`() {
        assertEquals(0, SpreadLayout.single(0).count)
        assertEquals(0, SpreadLayout.paired(0, emptySet(), isOffset = true).count)
    }

    @Test
    fun `landscape pairs consecutive pages`() {
        assertEquals(
            listOf(listOf(0, 1), listOf(2, 3), listOf(4, 5)),
            shape(SpreadLayout.paired(6, emptySet(), isOffset = false)),
        )
    }

    @Test
    fun `an odd page count leaves the last page alone rather than dropping it`() {
        assertEquals(
            listOf(listOf(0, 1), listOf(2, 3), listOf(4)),
            shape(SpreadLayout.paired(5, emptySet(), isOffset = false)),
        )
    }

    @Test
    fun `a wide page is shown alone, never split across two turns`() {
        // Page 2 is declared a double-page spread, so it takes a slot of its own -- and
        // page 3 cannot be paired backwards into it, so the run resumes at 3-4.
        assertEquals(
            listOf(listOf(0, 1), listOf(2), listOf(3, 4), listOf(5)),
            shape(SpreadLayout.paired(6, setOf(2), isOffset = false)),
        )
    }

    @Test
    fun `the page before a wide one is not paired into it`() {
        // Page 3 is wide, so page 2 has nothing to face and stands alone too.
        assertEquals(
            listOf(listOf(0, 1), listOf(2), listOf(3), listOf(4, 5)),
            shape(SpreadLayout.paired(6, setOf(3), isOffset = false)),
        )
    }

    @Test
    fun `two wide pages in a row each stand alone`() {
        assertEquals(
            listOf(listOf(0), listOf(1), listOf(2), listOf(3)),
            shape(SpreadLayout.paired(4, setOf(1, 2), isOffset = false)),
        )
    }

    @Test
    fun `the offset stands the cover alone and shifts everything after it`() {
        assertEquals(
            listOf(listOf(0), listOf(1, 2), listOf(3, 4), listOf(5)),
            shape(SpreadLayout.paired(6, emptySet(), isOffset = true)),
        )
    }

    @Test
    fun `a page knows which slot it is in, on either side of a pair`() {
        val layout = SpreadLayout.paired(6, setOf(2), isOffset = false)
        assertEquals(0, layout.slotContaining(0))
        assertEquals(0, layout.slotContaining(1))
        assertEquals(1, layout.slotContaining(2))
        assertEquals(2, layout.slotContaining(4))
        assertEquals(3, layout.slotContaining(5))
    }

    @Test
    fun `a page outside the publication resolves to the first slot rather than crashing`() {
        val layout = SpreadLayout.single(3)
        assertEquals(0, layout.slotContaining(99))
        assertEquals(0, layout.slotContaining(-1))
        assertNull(layout.slotAt(99))
    }

    @Test
    fun `a publication of nothing but wide pages has no pairing to offset`() {
        assertFalse(SpreadLayout.paired(3, setOf(0, 1, 2), isOffset = false).hasPairs)
        assertTrue(SpreadLayout.paired(4, emptySet(), isOffset = false).hasPairs)
        assertFalse(SpreadLayout.single(4).hasPairs)
    }
}
