package app.storyarc.core.designsystem.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Task 19.5: "the Android readers do not avoid the hinge". The two readers each draw one of
 * two shapes -- a spread of two pages, or one page on its own -- and [hingeSpreadSplit] and
 * [hingeInset] are the whole rule behind both, asked without a window or a device so the
 * answer is decidable on a plain JVM.
 */
class HingeAvoidanceTest {

    @Test
    fun `no hinge splits a spread into equal halves with no gap`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = null, hingeEnd = null)

        assertEquals(400f, split.leadingWidth, 0f)
        assertEquals(0f, split.gap, 0f)
        assertEquals(400f, split.trailingWidth, 0f)
    }

    @Test
    fun `a hinge entirely past the container's own width is not a hinge to avoid`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 900f, hingeEnd = 950f)

        assertEquals(0f, split.gap, 0f)
        assertEquals(400f, split.leadingWidth, 0f)
    }

    @Test
    fun `a hinge entirely before the container's own start is not a hinge to avoid`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = -100f, hingeEnd = -20f)

        assertEquals(0f, split.gap, 0f)
    }

    @Test
    fun `a centred hinge gives each half the room up to its own edge`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 380f, hingeEnd = 420f)

        assertEquals(380f, split.leadingWidth, 0f)
        assertEquals(40f, split.gap, 0f)
        assertEquals(380f, split.trailingWidth, 0f)
    }

    @Test
    fun `a hinge nearer the start gives the trailing half the room`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 100f, hingeEnd = 140f)

        assertEquals(100f, split.leadingWidth, 0f)
        assertEquals(40f, split.gap, 0f)
        assertEquals(660f, split.trailingWidth, 0f)
    }

    @Test
    fun `a hinge that only partly overlaps the container is clamped to it`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = -50f, hingeEnd = 50f)

        assertEquals(0f, split.leadingWidth, 0f)
        assertEquals(50f, split.gap, 0f)
        assertEquals(750f, split.trailingWidth, 0f)
    }

    @Test
    fun `no hinge to split on means no inset`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = null, hingeEnd = null)

        assertNull(hingeInset(split))
    }

    @Test
    fun `a hinge nearer the start insets a single page onto the trailing side`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 100f, hingeEnd = 140f)

        val inset = hingeInset(split)

        assertEquals(660f, inset?.width ?: -1f, 0f)
        assertEquals(false, inset?.atStart)
    }

    @Test
    fun `a hinge nearer the end insets a single page onto the leading side`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 660f, hingeEnd = 700f)

        val inset = hingeInset(split)

        assertEquals(660f, inset?.width ?: -1f, 0f)
        assertEquals(true, inset?.atStart)
    }

    @Test
    fun `a centred hinge breaks its tie to the leading side`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 380f, hingeEnd = 420f)

        val inset = hingeInset(split)

        assertTrue(inset?.atStart == true)
        assertEquals(380f, inset?.width ?: -1f, 0f)
    }
}
