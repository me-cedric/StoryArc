package app.storyarc.feature.epubreader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The rule that decides whether a finished drag was a page turn.
 *
 * A plain JVM test rather than an instrumented one: this is arithmetic, and the touch
 * dispatch around it is Android's contract rather than this project's. iOS pins the same
 * rule in `ReflowableTurnTests`.
 */
class TurnDragTest {

    private val threshold = 40f

    @Test
    fun `a drag leftwards past the threshold goes forward`() {
        assertEquals(true, TurnDrag.direction(travel = -41f, threshold = threshold))
    }

    @Test
    fun `a drag rightwards past the threshold goes back`() {
        assertEquals(false, TurnDrag.direction(travel = 41f, threshold = threshold))
    }

    @Test
    fun `a drag short of the threshold turns nothing`() {
        assertNull(TurnDrag.direction(travel = -39f, threshold = threshold))
        assertNull(TurnDrag.direction(travel = 39f, threshold = threshold))
    }

    @Test
    fun `the threshold itself has not been passed`() {
        assertNull(TurnDrag.direction(travel = -40f, threshold = threshold))
        assertNull(TurnDrag.direction(travel = 40f, threshold = threshold))
    }

    @Test
    fun `a finger that did not move turns nothing`() {
        assertNull(TurnDrag.direction(travel = 0f, threshold = threshold))
    }

    /**
     * The two phases have to divide the whole turn, or the name stops being true: Fast
     * fade is the mode a reader picks to spend the least time between pages.
     */
    @Test
    fun `the two fade phases together take the stated duration`() {
        assertEquals(FadeTurn.DURATION_MS, (FadeTurn.DURATION_MS / 2) * 2)
    }
}
