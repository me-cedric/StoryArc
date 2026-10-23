package app.storyarc.core.designsystem.theme

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The one hex parser, which replaced five. Three of those drew black for a bad value, one
 * `Unspecified` and one null; the callers keep those fallbacks, so this answers null and
 * nothing else for anything that is not `#rrggbb`.
 */
class HexColourTest {

    @Test
    fun `an rrggbb string is the opaque colour, with or without its hash`() {
        assertEquals(Color(0xFFEC7C27), hexColour("#EC7C27"))
        assertEquals(Color(0xFFEC7C27), hexColour("ec7c27"))
        assertEquals(Color.Black, hexColour("#000000"))
    }

    @Test
    fun `anything that is not six hex digits is null`() {
        assertNull(hexColour(null))
        assertNull(hexColour(""))
        assertNull(hexColour("#FFF"))
        assertNull(hexColour("#GGGGGG"))
        assertNull(hexColour("#FFFFFFFF"))
    }
}
