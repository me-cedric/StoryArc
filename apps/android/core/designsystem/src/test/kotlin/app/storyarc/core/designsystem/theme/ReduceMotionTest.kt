package app.storyarc.core.designsystem.theme

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `page-transitions`: the animator duration scale Android answers Reduce Motion with.
 */
class ReduceMotionTest {
    @Test
    fun `a zero scale is reduce motion`() {
        assertTrue(isReduceMotionScale(0f))
    }

    @Test
    fun `any other scale is not, including the default`() {
        assertFalse(isReduceMotionScale(1f))
        assertFalse(isReduceMotionScale(0.5f))
        assertFalse(isReduceMotionScale(2f))
    }
}
