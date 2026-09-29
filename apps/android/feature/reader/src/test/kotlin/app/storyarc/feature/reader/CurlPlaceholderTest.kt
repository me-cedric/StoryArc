package app.storyarc.feature.reader

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The sheet a curl turns to while that page has not decoded (task 8.4).
 *
 * `page-transitions` "The next page is not ready": the turn "runs against a placeholder
 * holding the correct aspect ratio".
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CurlPlaceholderTest {

    private val decoded = mapOf(2 to "page two")

    private fun sheet(display: Int?) =
        CurlPlaceholder.sheet(display, { decoded[it] }) { "placeholder for $it" }

    @Test
    fun `a decoded neighbour is the page itself`() {
        assertEquals("page two", sheet(2))
    }

    @Test
    fun `a neighbour still decoding is the placeholder, not the outgoing page`() {
        assertEquals("placeholder for 3", sheet(3))
    }

    @Test
    fun `past either end there is no sheet, so nothing turns`() {
        assertNull(sheet(null))
    }

    @Test
    fun `the placeholder holds the page's own proportions`() {
        assertEquals(64 to 96, CurlPlaceholder.size(2f / 3f))
        assertEquals(128 to 64, CurlPlaceholder.size(2f))
        assertEquals(64 to 96, CurlPlaceholder.size(0f))
    }

    @Test
    fun `the placeholder is the matte colour, edge to edge`() {
        val matte = Color(0xFF334455)
        val bitmap = CurlPlaceholder.bitmap(0.5f, matte)
        assertEquals(64 to 128, bitmap.width to bitmap.height)
        assertEquals(matte.toArgb(), bitmap.getPixel(0, 0))
        assertEquals(matte.toArgb(), bitmap.getPixel(63, 127))
    }
}
