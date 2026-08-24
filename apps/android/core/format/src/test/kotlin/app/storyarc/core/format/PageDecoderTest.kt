package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The arithmetic half of page decoding, testable without a device.
 *
 * The decode itself needs the Android framework, so it lives in
 * `PageDecoderInstrumentedTest` and runs on an emulator. Splitting it this way
 * means the parts that can be checked cheaply are, and the parts that cannot are
 * still checked rather than assumed.
 */
class PageDecoderTest {
    @Test
    fun `target size bounds the longest edge and keeps the aspect ratio`() {
        val size = PageDecoder.targetSize(2000, 3000, 600)

        assertEquals(400, size.width)
        assertEquals(600, size.height)
    }

    @Test
    fun `a landscape page is bounded on its width`() {
        val size = PageDecoder.targetSize(3000, 2000, 600)

        assertEquals(600, size.width)
        assertEquals(400, size.height)
    }

    @Test
    fun `asking for more than the source has does not upscale`() {
        val size = PageDecoder.targetSize(2000, 3000, 9000)

        assertEquals(2000, size.width)
        assertEquals(3000, size.height)
    }

    @Test
    fun `a very aggressive bound never rounds a dimension to zero`() {
        val size = PageDecoder.targetSize(2000, 3, 1)

        assertTrue(size.width >= 1)
        assertTrue(size.height >= 1)
    }

    @Test
    fun `a double-page spread is detected from its aspect ratio`() {
        assertTrue(PageDecoder.isSpread(6, 3))
        assertFalse(PageDecoder.isSpread(2, 3))
    }

    @Test
    fun `a merely-slightly-wide page is not a spread`() {
        assertFalse(PageDecoder.isSpread(110, 100))
        assertTrue(PageDecoder.isSpread(200, 100))
        assertFalse(PageDecoder.isSpread(100, 0))
    }
}
