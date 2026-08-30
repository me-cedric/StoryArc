package app.storyarc.feature.library

import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The readable range of a cover, at every window width.
 *
 * `library-browsing`'s Adaptive-columns scenario: "the number of grid columns follows the
 * available width, **and cover size stays within the readable range defined in the design
 * tokens**". The first clause was [GridCells.Adaptive]'s; the second was nobody's, which is
 * the divergence this asserts is gone.
 *
 * Density 1, so a dp is a pixel and the numbers below are the ones in `CoverGrid`.
 *
 * There is no iOS mirror of this file. SwiftUI's `GridItem(.adaptive(minimum:maximum:))`
 * owns the same arithmetic inside the framework, and a test of it would be a test of
 * SwiftUI. What the two platforms share is the pair of bounds, not the code that applies
 * them.
 */
class BoundedAdaptiveTest {

    private val density = Density(1f)
    private val cells = BoundedAdaptive(minSize = MINIMUM.dp, maxSize = MAXIMUM.dp)

    private fun sizes(available: Int, spacing: Int = SPACING): List<Int> =
        with(cells) { with(density) { calculateCrossAxisCellSizes(available, spacing) } }

    @Test
    fun `a phone-width window fits three columns`() {
        val columns = sizes(available = 392)
        assertEquals(3, columns.size)
        assertTrue(columns.all { it in MINIMUM..MAXIMUM })
    }

    @Test
    fun `a tablet-width window fits more columns and keeps them readable`() {
        val columns = sizes(available = 1024)
        assertEquals(8, columns.size)
        assertTrue(columns.all { it in MINIMUM..MAXIMUM })
    }

    @Test
    fun `a narrow window caps its single column at the maximum`() {
        // The divergence itself: `GridCells.Adaptive` returns one column of 220 here, and
        // a single cover fills the window.
        assertEquals(listOf(MAXIMUM), sizes(available = 220))
    }

    @Test
    fun `no window width makes a cover wider than the maximum`() {
        for (available in 1..2400) {
            val columns = sizes(available)
            assertTrue(
                "a $available px window produced $columns",
                columns.all { it <= MAXIMUM },
            )
        }
    }

    @Test
    fun `below the cap the columns fill the window exactly`() {
        val available = 1001
        val columns = sizes(available)
        assertEquals(available, columns.sum() + SPACING * (columns.size - 1))
    }

    @Test
    fun `a window narrower than one cover still has a column`() {
        assertEquals(listOf(40), sizes(available = 40))
    }

    @Test
    fun `two of the same bounds are the same value`() {
        assertEquals(BoundedAdaptive(108.dp, 168.dp), BoundedAdaptive(108.dp, 168.dp))
        assertEquals(
            BoundedAdaptive(108.dp, 168.dp).hashCode(),
            BoundedAdaptive(108.dp, 168.dp).hashCode(),
        )
    }

    private companion object {
        const val MINIMUM = 108
        const val MAXIMUM = 168
        const val SPACING = 16
    }
}
