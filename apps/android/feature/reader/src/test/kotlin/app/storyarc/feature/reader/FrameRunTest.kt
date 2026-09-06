package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * That the instrument counts frames correctly, which is the only part of *Frame budget* a
 * build machine can settle.
 *
 * `page-transitions` requires a transition to hold "the display's refresh rate, and a dropped
 * frame during a turn is treated as a defect". An emulator draws at its host's refresh rate,
 * so a rate measured here would be a fact about the host and about nothing else. **No case
 * below asserts a frame rate, and none may be added.** Each case hands [FrameRun] a timetable
 * it invented and checks the arithmetic that comes back.
 *
 * The interval every case uses is 0.01 seconds. No display runs at that rate, so no case can
 * be misread as a claim about a device. The rate itself is read from the display at run time
 * by `FrameProbe` and is reported, never asserted.
 *
 * iOS's `FrameRunTests` asserts the same table, case for case.
 */
class FrameRunTest {

    /** Deliberately no display's frame interval. */
    private val interval = 0.01

    // Counting

    @Test
    fun `it counts every frame it is handed`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        for (step in 0 until 10) run.record(at = step * interval, expecting = interval)
        assertEquals(10, run.delivered)
        assertEquals(0, run.dropped)
    }

    @Test
    fun `a frame that never arrived is one dropped frame`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        run.record(at = interval, expecting = interval)
        run.record(at = interval * 3, expecting = interval)
        assertEquals(3, run.delivered)
        assertEquals(1, run.dropped)
    }

    @Test
    fun `two frames missing from one gap are two dropped frames`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        run.record(at = interval * 3, expecting = interval)
        assertEquals(2, run.dropped)
    }

    @Test
    fun `the span is the time from the first frame to the last`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 5.0, expecting = interval)
        run.record(at = 5.0 + interval, expecting = interval)
        run.record(at = 5.25, expecting = interval)
        assertEquals(0.25, run.span, 0.000001)
    }

    // What it refuses to infer

    @Test
    fun `an interval the display did not report infers no drops`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = 0.0)
        run.record(at = 10.0, expecting = 0.0)
        assertEquals(2, run.delivered)
        assertEquals(0, run.dropped)
    }

    @Test
    fun `a frame stamped no later than the one before it drops nothing`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = interval, expecting = interval)
        run.record(at = interval, expecting = interval)
        run.record(at = 0.0, expecting = interval)
        assertEquals(3, run.delivered)
        assertEquals(0, run.dropped)
    }

    @Test
    fun `a gap wide enough to be nonsense is counted but bounded`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        run.record(at = 1_000_000.0, expecting = interval)
        assertEquals(999, run.dropped)
    }

    // Not running when no page is turning

    @Test
    fun `a run that has not begun counts nothing`() {
        val run = FrameRun(isEnabled = true)
        run.record(at = 0.0, expecting = interval)
        assertFalse(run.isRecording)
        assertEquals(0, run.delivered)
    }

    @Test
    fun `a run that has ended counts nothing more`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        run.end()
        run.record(at = interval, expecting = interval)
        assertFalse(run.isRecording)
        assertEquals(1, run.delivered)
    }

    @Test
    fun `a disabled run never starts, so an unarmed build counts nothing`() {
        val run = FrameRun(isEnabled = false)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        assertFalse(run.isRecording)
        assertEquals(0, run.delivered)
    }

    @Test
    fun `beginning again while a turn is still running keeps the count`() {
        val run = FrameRun(isEnabled = true)
        run.begin()
        run.record(at = 0.0, expecting = interval)
        run.begin()
        run.record(at = interval, expecting = interval)
        assertEquals(2, run.delivered)
    }
}
