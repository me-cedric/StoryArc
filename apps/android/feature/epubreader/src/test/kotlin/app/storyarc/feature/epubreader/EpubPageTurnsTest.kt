package app.storyarc.feature.epubreader

import android.view.KeyEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What [EpubReaderActivity] does with a tap or a key: the routing in [EpubPageTurns], which
 * `EdgeTapAndKeysTest`'s lookup tables feed.
 *
 * A turn asks for the navigator once, so counting the asks counts the turns. There is no
 * navigator here, which is the activity's own state before the book opens.
 */
class EpubPageTurnsTest {

    private var turns = 0
    private var chrome = 0

    private fun pageTurns(fadeOwnsTheTurn: Boolean = false) = EpubPageTurns(
        scope = CoroutineScope(Dispatchers.Unconfined),
        navigator = { turns++; null },
        dipHost = { error("no dip without a navigator") },
        dipIndex = 1,
        pageColour = { 0 },
        reduceMotion = { false },
        fadeOwnsTheTurn = { fadeOwnsTheTurn },
    )

    @Test
    fun `a volume key changes the volume while the setting is off`() {
        val handled = pageTurns().key(KeyEvent.KEYCODE_VOLUME_DOWN, volumeTurns = false) { chrome++ }

        assertFalse("the key goes back to the system", handled)
        assertEquals(0, turns)
    }

    @Test
    fun `a volume key turns the page while the setting is on`() {
        val handled = pageTurns().key(KeyEvent.KEYCODE_VOLUME_UP, volumeTurns = true) { chrome++ }

        assertTrue(handled)
        assertEquals(1, turns)
    }

    @Test
    fun `enter toggles the chrome and turns nothing`() {
        assertTrue(pageTurns().key(KeyEvent.KEYCODE_ENTER, volumeTurns = false) { chrome++ })
        assertEquals(1, chrome)
        assertEquals(0, turns)
    }

    @Test
    fun `an arrow turns the page whatever the volume setting`() {
        assertTrue(pageTurns().key(KeyEvent.KEYCODE_DPAD_RIGHT, volumeTurns = false) { chrome++ })
        assertEquals(1, turns)
    }

    @Test
    fun `another key is left to the activity`() {
        assertFalse(pageTurns().key(KeyEvent.KEYCODE_A, volumeTurns = true) { chrome++ })
        assertEquals(0, turns + chrome)
    }

    @Test
    fun `an edge tap turns in fast fade and in slide alike, and the middle reveals the chrome`() {
        pageTurns(fadeOwnsTheTurn = true).tap(x = 1100f, width = 1200f, tapTurnsPages = true) { chrome++ }
        pageTurns(fadeOwnsTheTurn = false).tap(x = 100f, width = 1200f, tapTurnsPages = true) { chrome++ }
        pageTurns().tap(x = 600f, width = 1200f, tapTurnsPages = true) { chrome++ }

        assertEquals(2, turns)
        assertEquals(1, chrome)
    }

    @Test
    fun `with the tap zones off an edge tap reveals the chrome`() {
        pageTurns().tap(x = 100f, width = 1200f, tapTurnsPages = false) { chrome++ }

        assertEquals(0, turns)
        assertEquals(1, chrome)
    }
}
