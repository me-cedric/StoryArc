package app.storyarc.navigation

import androidx.compose.runtime.saveable.SaverScope
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
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

    /** What a `Saver` is handed at save time. Nothing here consults it. */
    private object TestSaverScope : SaverScope {
        override fun canBeSaved(value: Any): Boolean = true
    }

    private fun collection() = Screen.Collection(UUID.randomUUID())

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(contentDigest = title),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `opens on the home destination with nothing stacked on it`() {
        val navigation = AppNavigation()

        assertEquals(AppDestination.HOME, navigation.destination)
        assertNull(navigation.current)
        assertFalse(navigation.canGoBack)
    }

    /**
     * The destination set, in the order a reader meets it.
     *
     * **This asserted three until search became a destination**, and the promise it was
     * protecting is unchanged: the set does not grow in response to anything the reader
     * configures. *Fixed* was always the promise; *three* never was. Search is here because
     * the app puts it here, once, not because a source was added — the cases below still hold
     * a nine-server registry to the same four.
     *
     * Four is inside Material's own range for both controls this list builds — 3–5 for the
     * navigation bar, 3–7 for the collapsed rail. iOS's `LibraryDestinationTests` asserts the
     * same four in the same order.
     *
     * **The sentence above claimed cases that did not exist until 2026-09-05.** It said the
     * cases below held a nine-server registry to the same four, and no case below took a
     * registry at all — `AppDestination` had nothing to hand one to. The three cases that
     * follow are that claim made true, against task 1.3.
     */
    @Test
    fun `there are exactly four destinations`() {
        assertEquals(
            listOf(
                AppDestination.HOME,
                AppDestination.LIBRARY,
                AppDestination.DOWNLOADS,
                AppDestination.SEARCH,
            ),
            AppDestination.entries.toList(),
        )
    }

    @Test
    fun `a reader who has added nothing gets all four`() {
        // A destination set that filled in as sources were added would be a navigation
        // control that looked broken on first launch -- and Downloads is exactly the
        // destination a reader with no server still needs.
        assertEquals(AppDestination.entries.toList(), AppDestination.all(emptyList()))
    }

    @Test
    fun `a source of every kind changes nothing`() {
        val sources = SourceKind.entries.map { Source(displayName = "A $it", kind = it) }

        assertEquals(AppDestination.entries.toList(), AppDestination.all(sources))
    }

    @Test
    fun `nine servers do not put a navigation control over its ceiling`() {
        // The promise `navigation-shell` makes: the app "SHALL NOT add, remove or reorder a
        // destination in response to anything the reader configures". The shape it is
        // written against is the old sidebar, which grew a row per browsable source -- nine
        // servers was eleven rows, over Material's ceiling for the collapsed rail, and a
        // reader's own navigation reading back the transports their books arrived over.
        //
        // Added, renamed, reordered and removed are all one assertion here, because the
        // registry is never consulted: there is no ordering of it and no membership of it
        // that the answer could depend on.
        val servers = (1..9).map {
            Source(displayName = "Server $it", kind = SourceKind.KAVITA_SERVER)
        }

        assertEquals(4, AppDestination.all(servers).size)
        assertEquals(AppDestination.entries.toList(), AppDestination.all(servers))
        assertEquals(AppDestination.all(servers), AppDestination.all(servers.reversed()))
        assertEquals(AppDestination.all(servers), AppDestination.all(servers.drop(4)))
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
    fun `a rebuilt activity comes back to the destination it was on, at its root`() {
        val navigation = AppNavigation()
            .select(AppDestination.DOWNLOADS)
            .push(Screen.Settings())

        val saved = with(AppNavigation.Saver) { TestSaverScope.save(navigation) }
        val restored = AppNavigation.Saver.restore(requireNotNull(saved))

        assertEquals(AppDestination.DOWNLOADS, restored?.destination)
        assertNull(restored?.current)
    }

    @Test
    fun `an unreadable saved destination falls back to the one the app opens on`() {
        assertEquals(AppDestination.HOME, AppNavigation.Saver.restore("ELSEWHERE")?.destination)
    }

    @Test
    fun `popping an empty stack changes nothing`() {
        val navigation = AppNavigation().select(AppDestination.LIBRARY)

        assertEquals(navigation, navigation.pop())
    }

    @Test
    fun `a cover opens the publication's page inside the destination the reader was in`() {
        val chosen = publication("bone one")

        val navigation = AppNavigation().select(AppDestination.LIBRARY).openPage(chosen)

        // Inside the library, not somewhere else: `publication-detail` asks for the page to
        // open "within the destination they were already in".
        assertEquals(AppDestination.LIBRARY, navigation.destination)
        assertEquals(Screen.PublicationPage(chosen), navigation.current)
        // And back is the way they came, which is what makes the shelf's scroll, filters
        // and selection survive the trip.
        assertNull(navigation.back().current)
    }

    @Test
    fun `the page keeps the navigation control, and the reader does not`() {
        // A page is somewhere a reader *is*, so a lateral move out of it is one they may
        // legitimately want. The reader is a task they come back from.
        val page = Screen.PublicationPage(publication("bone one"))

        assertTrue(AppNavigation().push(page).showsNavigation)
        assertFalse(AppNavigation().push(Screen.Reader(publication("bone one"), "/x")).showsNavigation)
    }

    @Test
    fun `choosing the publication whose page is already showing is not a second page`() {
        // Its own series shelf can hold it, through a duplicate in the library or a reload
        // between the tap and the push. Stacking a second copy gives the reader a back press
        // that appears to do nothing.
        val chosen = publication("bone one")
        val navigation = AppNavigation().select(AppDestination.LIBRARY).openPage(chosen)

        assertEquals(navigation, navigation.openPage(chosen))
    }

    @Test
    fun `a page opened from a page stacks, so back is the way the reader came`() {
        val first = publication("bone one")
        val second = publication("bone two")

        val navigation = AppNavigation()
            .select(AppDestination.LIBRARY)
            .openPage(first)
            .openPage(second)

        assertEquals(Screen.PublicationPage(second), navigation.current)
        assertEquals(Screen.PublicationPage(first), navigation.back().current)
    }
}
