package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * How much of a publication the reader holds decoded, and what shrinks it.
 *
 * `comic-reader` names a floor — "at least the next three and previous one" — and an
 * override: "prefetch depth shrinks under memory pressure rather than the app being
 * terminated". iOS's `PrefetchWindowTests` asserts the same table.
 */
class PrefetchWindowTest {
    @Test
    fun `with nothing wrong, the window is the one the spec asks for`() {
        assertEquals(PrefetchWindow(ahead = 3, behind = 1), PrefetchWindow.under(MemoryPressure.NORMAL))
        assertEquals(PrefetchWindow.FULL, PrefetchWindow.under(MemoryPressure.NORMAL))
    }

    @Test
    fun `pressure narrows the window, and the more of it the narrower`() {
        val warned = PrefetchWindow.under(MemoryPressure.WARNING)
        val critical = PrefetchWindow.under(MemoryPressure.CRITICAL)
        assertTrue(warned.ahead < PrefetchWindow.FULL.ahead)
        assertTrue(critical.ahead < warned.ahead)
        assertTrue(critical.behind <= warned.behind)
    }

    @Test
    fun `under critical pressure only the page on screen is held`() {
        assertEquals(
            setOf(10),
            PrefetchWindow.under(MemoryPressure.CRITICAL).pages(around = 10, of = 100),
        )
    }

    @Test
    fun `the pressure lifting restores the full window rather than a smaller one`() {
        assertEquals(PrefetchWindow.FULL, PrefetchWindow.under(MemoryPressure.NORMAL))
    }

    @Test
    fun `the window is clamped to the publication rather than running off either end`() {
        assertEquals(setOf(0, 1, 2), PrefetchWindow.FULL.pages(around = 0, of = 3))
        assertEquals(setOf(8, 9), PrefetchWindow.FULL.pages(around = 9, of = 10))
    }

    @Test
    fun `the full window holds five pages in the middle of a long comic`() {
        assertEquals(setOf(49, 50, 51, 52, 53), PrefetchWindow.FULL.pages(around = 50, of = 200))
    }

    @Test
    fun `a window around a page that does not exist holds nothing`() {
        assertTrue(PrefetchWindow.FULL.pages(around = 0, of = 0).isEmpty())
    }
}
