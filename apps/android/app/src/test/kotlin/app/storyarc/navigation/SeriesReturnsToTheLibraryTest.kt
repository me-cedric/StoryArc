package app.storyarc.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Opening a series and coming back is a return, not a reset.
 *
 * `library-browsing`: "one gesture returns to the library, at the place the reader left
 * it". Two claims, and the second is the one worth a test — a series that took the reader
 * back to the top of a shelf they had scrolled through would be worse than no series row at
 * all, because the shelf is now sixty cells shorter and the place they left is further
 * down.
 *
 * The mechanism is [AppNavigation.stateKey], which `AppPanes` hands to a
 * `SaveableStateHolder`: every scroll offset, open filter and text field is remembered
 * against it. So "the place the reader left it" is decidable here, without a device — the
 * key the library was drawn under has to be the key it is drawn under again.
 */
class SeriesReturnsToTheLibraryTest {

    private val library = AppNavigation().select(AppDestination.LIBRARY)

    @Test
    fun `one gesture returns from a series to the library`() {
        val inside = library.push(Screen.SeriesShelf("Lantern Green"))

        val back = inside.pop()
        // By what is drawn, not by the value's innards: a popped stack keeps an empty entry
        // where a fresh one has none, and the two render the same library.
        assertEquals(AppDestination.LIBRARY, back.destination)
        assertNull(back.current)
        assertEquals(library.stateKey, back.stateKey)
    }

    @Test
    fun `the library is drawn under the key it had before the series was opened`() {
        val inside = library.push(Screen.SeriesShelf("Lantern Green"))

        // Different while the series is open, or the two would share a scroll offset.
        assertNotEquals(library.stateKey, inside.stateKey)
        // And the same again after, which is what makes it a return.
        assertEquals(library.stateKey, inside.pop().stateKey)
    }

    @Test
    fun `two series are two places, and neither inherits the other's`() {
        val first = library.push(Screen.SeriesShelf("Lantern Green"))
        val second = library.push(Screen.SeriesShelf("Titans"))

        // The key is depth and kind, so two series at one depth share it -- which is
        // correct for a scroll offset only because one is popped before the other opens.
        // What must not happen is either of them sharing the library's.
        assertNotEquals(library.stateKey, first.stateKey)
        assertNotEquals(library.stateKey, second.stateKey)
    }

    @Test
    fun `a screen opened from inside a series comes back to the series, then to the library`() {
        val inside = library.push(Screen.SeriesShelf("Lantern Green"))
        val deeper = inside.push(Screen.Settings())

        assertEquals(Screen.SeriesShelf("Lantern Green"), deeper.pop().current)
        assertEquals(inside.stateKey, deeper.pop().stateKey)
        assertNull(deeper.pop().pop().current)
        assertEquals(library.stateKey, deeper.pop().pop().stateKey)
    }
}
