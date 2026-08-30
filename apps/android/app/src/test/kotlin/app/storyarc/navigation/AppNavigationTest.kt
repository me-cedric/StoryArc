package app.storyarc.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The navigation model, asserted without a device.
 *
 * This is the reason the model is a value rather than a pile of composition state: the
 * behaviour `navigation-shell` specifies — each destination retracing its own path, a
 * destination surviving a visit to another one, a source never becoming a destination — is
 * decidable here, in milliseconds, rather than in an instrumented test nobody runs.
 */
class AppNavigationTest {

    private fun collection() = Screen.Collection(UUID.randomUUID())

    @Test
    fun `opens on the home destination with nothing stacked on it`() {
        val navigation = AppNavigation()

        assertEquals(AppDestination.HOME, navigation.destination)
        assertNull(navigation.current)
        assertFalse(navigation.canGoBack)
    }

    @Test
    fun `there are exactly three destinations`() {
        assertEquals(
            listOf(AppDestination.HOME, AppDestination.LIBRARY, AppDestination.DOWNLOADS),
            AppDestination.entries.toList(),
        )
    }

    @Test
    fun `back retraces the current destination's own path`() {
        val shelf = collection()
        val navigation = AppNavigation()
            .select(AppDestination.LIBRARY)
            .push(Screen.Shelves)
            .push(shelf)

        val once = navigation.back()
        assertEquals(Screen.Shelves, once.current)

        val twice = once.back()
        assertNull(twice.current)
        assertEquals(AppDestination.LIBRARY, twice.destination)
    }

    @Test
    fun `back from the root of a destination falls back to the one the app opens on`() {
        val navigation = AppNavigation().select(AppDestination.DOWNLOADS)

        assertTrue(navigation.canGoBack)
        assertEquals(AppDestination.HOME, navigation.back().destination)
    }

    @Test
    fun `back at the home root is the system's to answer`() {
        val navigation = AppNavigation()

        assertFalse(navigation.canGoBack)
        assertEquals(navigation, navigation.back())
    }

    @Test
    fun `leaving a destination and returning is a return rather than a reset`() {
        val navigation = AppNavigation()
            .select(AppDestination.LIBRARY)
            .push(Screen.Shelves)
            .select(AppDestination.DOWNLOADS)

        assertNull(navigation.current)

        val back = navigation.select(AppDestination.LIBRARY)
        assertEquals(Screen.Shelves, back.current)
    }

    @Test
    fun `each destination keeps its own path`() {
        val shelf = collection()
        val navigation = AppNavigation()
            .select(AppDestination.LIBRARY)
            .push(Screen.Shelves)
            .select(AppDestination.HOME)
            .push(shelf)

        assertEquals(shelf, navigation.current)
        assertEquals(Screen.Shelves, navigation.select(AppDestination.LIBRARY).current)
    }

    @Test
    fun `choosing the destination already showing returns it to its root`() {
        val navigation = AppNavigation()
            .select(AppDestination.LIBRARY)
            .push(Screen.Shelves)
            .push(collection())
            .select(AppDestination.LIBRARY)

        assertNull(navigation.current)
        assertEquals(AppDestination.LIBRARY, navigation.destination)
    }

    @Test
    fun `a quick action opens a destination at its root whatever was stacked on it`() {
        val navigation = AppNavigation()
            .select(AppDestination.LIBRARY)
            .push(Screen.Shelves)
            .select(AppDestination.HOME)
            .open(AppDestination.LIBRARY)

        assertEquals(AppDestination.LIBRARY, navigation.destination)
        assertNull(navigation.current)
    }

    @Test
    fun `a sideways move replaces the screen rather than stacking onto it`() {
        val first = collection()
        val second = collection()
        val navigation = AppNavigation().push(Screen.Shelves).push(first).replace(second)

        assertEquals(second, navigation.current)
        assertEquals(Screen.Shelves, navigation.back().current)
    }

    @Test
    fun `replacing at a root pushes, so nothing is drawn with an empty stack`() {
        val navigation = AppNavigation().replace(Screen.Shelves)

        assertEquals(Screen.Shelves, navigation.current)
    }

    @Test
    fun `the navigation control is drawn except where a screen owns the window`() {
        val browsing = AppNavigation().select(AppDestination.LIBRARY).push(Screen.Shelves)
        assertTrue(browsing.showsNavigation)

        assertFalse(browsing.push(Screen.Settings()).showsNavigation)
    }

    @Test
    fun `two positions of the same depth and kind share their saved state`() {
        val navigation = AppNavigation().select(AppDestination.LIBRARY).push(Screen.Shelves)

        assertEquals(navigation.stateKey, navigation.pop().push(Screen.Shelves).stateKey)
    }

    @Test
    fun `a deeper position has a saved state of its own`() {
        val navigation = AppNavigation().select(AppDestination.LIBRARY).push(Screen.Shelves)

        assertTrue(navigation.stateKey != navigation.push(collection()).stateKey)
    }

    @Test
    fun `popping an empty stack changes nothing`() {
        val navigation = AppNavigation().select(AppDestination.LIBRARY)

        assertEquals(navigation, navigation.pop())
    }
}
