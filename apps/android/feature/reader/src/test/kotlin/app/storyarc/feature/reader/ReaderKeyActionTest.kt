package app.storyarc.feature.reader

import androidx.compose.ui.input.key.Key
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which key does what in the comic reader. `page-transitions`: arrow, page and space keys
 * turn the page, and Enter toggles the chrome -- no key did that before this.
 */
class ReaderKeyActionTest {

    @Test
    fun `the arrow keys turn by a display step`() {
        assertEquals(ReaderKeyAction.TurnBackward, ReaderKeyAction.of(Key.DirectionLeft))
        assertEquals(ReaderKeyAction.TurnForward, ReaderKeyAction.of(Key.DirectionRight))
    }

    @Test
    fun `page and space keys turn in reading order`() {
        assertEquals(ReaderKeyAction.PreviousInOrder, ReaderKeyAction.of(Key.PageUp))
        assertEquals(ReaderKeyAction.NextInOrder, ReaderKeyAction.of(Key.PageDown))
        assertEquals(ReaderKeyAction.NextInOrder, ReaderKeyAction.of(Key.Spacebar))
    }

    @Test
    fun `enter toggles the chrome, from either enter key`() {
        assertEquals(ReaderKeyAction.ToggleChrome, ReaderKeyAction.of(Key.Enter))
        assertEquals(ReaderKeyAction.ToggleChrome, ReaderKeyAction.of(Key.NumPadEnter))
    }

    @Test
    fun `an unmapped key does nothing, so typing in a search field is not a turn`() {
        assertNull(ReaderKeyAction.of(Key.A))
    }
}
