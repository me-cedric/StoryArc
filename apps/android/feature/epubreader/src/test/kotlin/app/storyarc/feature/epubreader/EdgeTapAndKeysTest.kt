package app.storyarc.feature.epubreader

import android.view.KeyEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Edge taps, keys and volume buttons for the reflowable reader -- all three reach
 * [EpubReaderActivity] (a tap through Readium's input listener, a key or a volume press
 * through `onKeyDown`), and none of them turned a page or toggled the chrome before this.
 *
 * Plain JVM tests: this is arithmetic and a lookup table, not Android's own contract.
 * iOS pins the same rules in `ReflowableTapZonesTests` and `EpubTurnKeyTests`.
 */
class EdgeTapAndKeysTest {

    @Test
    fun `the leading third turns back and the trailing third turns forward`() {
        assertEquals(false, EdgeTap.outcome(x = 360f, width = 1200f, tapTurnsPages = true))
        assertEquals(true, EdgeTap.outcome(x = 840f, width = 1200f, tapTurnsPages = true))
    }

    @Test
    fun `the middle third reveals the chrome instead`() {
        assertNull(EdgeTap.outcome(x = 600f, width = 1200f, tapTurnsPages = true))
    }

    @Test
    fun `with the setting off every tap reveals the chrome`() {
        assertNull(EdgeTap.outcome(x = 360f, width = 1200f, tapTurnsPages = false))
        assertNull(EdgeTap.outcome(x = 840f, width = 1200f, tapTurnsPages = false))
    }

    @Test
    fun `arrow, page and space keys turn the page`() {
        assertEquals(EpubTurnKey.TurnBackward, EpubTurnKey.of(KeyEvent.KEYCODE_DPAD_LEFT))
        assertEquals(EpubTurnKey.TurnBackward, EpubTurnKey.of(KeyEvent.KEYCODE_PAGE_UP))
        assertEquals(EpubTurnKey.TurnForward, EpubTurnKey.of(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertEquals(EpubTurnKey.TurnForward, EpubTurnKey.of(KeyEvent.KEYCODE_PAGE_DOWN))
        assertEquals(EpubTurnKey.TurnForward, EpubTurnKey.of(KeyEvent.KEYCODE_SPACE))
    }

    @Test
    fun `enter toggles the chrome, from either enter key`() {
        assertEquals(EpubTurnKey.ToggleChrome, EpubTurnKey.of(KeyEvent.KEYCODE_ENTER))
        assertEquals(EpubTurnKey.ToggleChrome, EpubTurnKey.of(KeyEvent.KEYCODE_NUMPAD_ENTER))
    }

    @Test
    fun `an unmapped key does nothing, so typing in the search field is not a turn`() {
        assertNull(EpubTurnKey.of(KeyEvent.KEYCODE_A))
    }

    @Test
    fun `volume-down is always forward, volume-up always back`() {
        assertEquals(true, volumeTurnsForward(KeyEvent.KEYCODE_VOLUME_DOWN))
        assertEquals(false, volumeTurnsForward(KeyEvent.KEYCODE_VOLUME_UP))
    }

    @Test
    fun `another key is not a volume turn`() {
        assertNull(volumeTurnsForward(KeyEvent.KEYCODE_A))
    }
}
