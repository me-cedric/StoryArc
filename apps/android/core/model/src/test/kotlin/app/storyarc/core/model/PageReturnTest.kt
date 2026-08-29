package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The way back from a slider jump.
 *
 * `comic-reader`: "releasing jumps there, with a control to return to the previous
 * position". iOS's `PageReturnTests` asserts the same cases.
 */
class PageReturnTest {
    @Test
    fun `a jump marks where it came from`() {
        assertEquals(4, PageReturn().jumped(4, 180).mark)
    }

    @Test
    fun `a jump that goes nowhere leaves no mark`() {
        assertNull(PageReturn().jumped(4, 4).mark)
    }

    @Test
    fun `a step of one page is a turn, and a turn is undone by turning back`() {
        assertNull(PageReturn().jumped(4, 5).mark)
        assertNull(PageReturn().jumped(4, 3).mark)
    }

    @Test
    fun `a second jump offers the place the second one started, not the first`() {
        val marked = PageReturn().jumped(4, 180).jumped(180, 60)
        assertEquals(180, marked.mark)
    }

    @Test
    fun `reading back to the mark retires the offer`() {
        val marked = PageReturn().jumped(4, 180)
        assertEquals(4, marked.moved(179).mark)
        assertNull(marked.moved(4).mark)
    }

    @Test
    fun `taking the mark stops it being offered twice`() {
        assertNull(PageReturn().jumped(4, 180).taken().mark)
    }

    @Test
    fun `a jump backwards is a jump too - the page slider runs both ways`() {
        assertEquals(180, PageReturn().jumped(180, 4).mark)
    }
}
