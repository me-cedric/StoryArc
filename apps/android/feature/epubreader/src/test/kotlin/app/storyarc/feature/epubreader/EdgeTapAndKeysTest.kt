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

    /**
     * Task 9.12: a right-to-left book mirrors the band, the way the comic reader's own
     * display order mirrors its edge taps for free (`ZoomablePage`). This reader has no
     * display-order layer -- Readium paginates the text -- so the mirror happens here.
     */
    @Test
    fun `under right-to-left, the edge band turns the opposite way`() {
        assertEquals(true, EdgeTap.outcome(x = 360f, width = 1200f, tapTurnsPages = true, isRightToLeft = true))
        assertEquals(false, EdgeTap.outcome(x = 840f, width = 1200f, tapTurnsPages = true, isRightToLeft = true))
        assertNull(EdgeTap.outcome(x = 600f, width = 1200f, tapTurnsPages = true, isRightToLeft = true))
    }

    /**
     * Only the d-pad arrows are spatial. Page Up/Down and Space move "the next page to
     * read" on either reading direction, the same split `ReaderKeyAction` draws for the
     * comic reader.
     */
    @Test
    fun `under right-to-left, the d-pad arrows swap but page and space do not`() {
        assertEquals(EpubTurnKey.TurnForward, EpubTurnKey.of(KeyEvent.KEYCODE_DPAD_LEFT, isRightToLeft = true))
        assertEquals(EpubTurnKey.TurnBackward, EpubTurnKey.of(KeyEvent.KEYCODE_DPAD_RIGHT, isRightToLeft = true))
        assertEquals(EpubTurnKey.TurnBackward, EpubTurnKey.of(KeyEvent.KEYCODE_PAGE_UP, isRightToLeft = true))
        assertEquals(EpubTurnKey.TurnForward, EpubTurnKey.of(KeyEvent.KEYCODE_PAGE_DOWN, isRightToLeft = true))
        assertEquals(EpubTurnKey.TurnForward, EpubTurnKey.of(KeyEvent.KEYCODE_SPACE, isRightToLeft = true))
    }

    @Test
    fun `a leftward drag turns forward in a left-to-right book and backward in a right-to-left one`() {
        assertEquals(true, TurnDrag.direction(travel = -60f, threshold = 40f))
        assertEquals(false, TurnDrag.direction(travel = -60f, threshold = 40f, isRightToLeft = true))
        assertEquals(false, TurnDrag.direction(travel = 60f, threshold = 40f))
        assertEquals(true, TurnDrag.direction(travel = 60f, threshold = 40f, isRightToLeft = true))
    }

    @Test
    fun `a drag that does not pass the threshold turns nothing, in either direction`() {
        assertNull(TurnDrag.direction(travel = 10f, threshold = 40f))
        assertNull(TurnDrag.direction(travel = 10f, threshold = 40f, isRightToLeft = true))
    }
}
