package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What one turn cost, as the ratio `CurlVerdict` judges a device by.
 *
 * `page-transitions`' *Frame budget* says a dropped frame during a turn "is treated as a
 * defect", and D11 turns that into a decision: a device whose curls keep missing frames stops
 * being offered the curl. This is the number that decision is taken on.
 *
 * **No case below asserts a frame rate**, for the reason `FrameRunTest` states: the interval
 * every case uses is 0.01 seconds, which no display runs at. iOS's `CurlCapabilityTests`
 * asserts the same table.
 */
class FrameStrainTest {

    /** Deliberately no display's frame interval. */
    private val interval = 0.01

    @Test
    fun `a turn of one frame says nothing, so it is not a measurement`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        assertNull(run.strain)
    }

    @Test
    fun `a turn that dropped nothing is exactly one, whatever its length`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        repeat(10) { step -> run.record(at = step * interval, expecting = interval) }
        assertEquals(0, run.dropped)
        assertEquals(1.0, run.strain!!, 0.001)
    }

    @Test
    fun `a turn that missed every other frame cost twice its budget`() {
        // Ten frames handed over with one missed between each pair: the app drew nine
        // intervals' worth of page in eighteen intervals of time.
        val run = FrameRun(isEnabled = true)
        run.begin()
        repeat(10) { step -> run.record(at = step * 2 * interval, expecting = interval) }
        assertEquals(9, run.dropped)
        assertEquals(2.0, run.strain!!, 0.001)
    }
}
