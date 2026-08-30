package app.storyarc.feature.reader

import android.content.ComponentCallbacks2
import app.storyarc.core.model.MemoryPressure
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Android's trim levels, read as the three states the reader knows.
 *
 * `comic-reader`: "prefetch depth shrinks under memory pressure rather than the app being
 * terminated". What counts as pressure is the platform's own vocabulary, and this is
 * where the seven levels collapse onto [MemoryPressure] — the table
 * `PrefetchWindowTest` then asserts.
 *
 * iOS has no mirror of this test: its three states come straight out of a dispatch
 * source, which reports them by name and has nothing to map.
 */
@Suppress("DEPRECATION")
class TrimPressureTest {
    @Test
    fun `a request for memory back narrows the window without emptying it`() {
        assertEquals(
            MemoryPressure.WARNING,
            trimPressure(ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE),
        )
        assertEquals(
            MemoryPressure.WARNING,
            trimPressure(ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW),
        )
    }

    @Test
    fun `the system choosing what to end empties the window`() {
        assertEquals(
            MemoryPressure.CRITICAL,
            trimPressure(ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL),
        )
    }

    @Test
    fun `the reader losing the screen counts as critical, because nothing is being read`() {
        assertEquals(
            MemoryPressure.CRITICAL,
            trimPressure(ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN),
        )
        assertEquals(
            MemoryPressure.CRITICAL,
            trimPressure(ComponentCallbacks2.TRIM_MEMORY_COMPLETE),
        )
    }

    @Test
    fun `a level below any of them is not pressure at all`() {
        assertEquals(MemoryPressure.NORMAL, trimPressure(0))
    }
}
