package app.storyarc

import app.storyarc.core.designsystem.theme.StoryArcWindowClass
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.navigation.AppDestination
import app.storyarc.navigation.AppNavigation
import app.storyarc.navigation.Screen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

/**
 * When the window is divided in two, and — much more to the point — when it is not.
 *
 * The whole rule is a function of a navigation and a width, so it is decidable here rather
 * than in an instrumented test nobody runs. That is also what keeps it honest: a rule spread
 * across a composable's conditionals would have exactly the cases below and no way to state
 * them.
 */
class PaneSplitTest {

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(contentDigest = title),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    private fun page(title: String) = Screen.PublicationPage(publication(title))

    private fun library(vararg stacked: Screen): AppNavigation =
        stacked.fold(AppNavigation().select(AppDestination.LIBRARY)) { at, screen -> at.push(screen) }

    @Test
    fun `a phone never gets two panes, whatever is on the path`() {
        assertNull(PaneSplit.of(library(), StoryArcWindowClass.COMPACT))
        assertNull(PaneSplit.of(library(page("Bone")), StoryArcWindowClass.COMPACT))
    }

    @Test
    fun `nor does a window that only has room for the rail`() {
        // The bug the five breakpoints exist to fix. 600 dp is where the rail arrives, and
        // for two years it was also where everything else arrived; a portrait tablet has
        // room for a rail and a shelf, and not for a shelf and a page beside it.
        assertNull(PaneSplit.of(library(page("Bone")), StoryArcWindowClass.MEDIUM))
    }

    @Test
    fun `an expanded window shows the shelf alone until a page is opened on it`() {
        assertEquals(
            PaneSplit(detail = null),
            PaneSplit.of(library(), StoryArcWindowClass.EXPANDED),
        )
    }

    @Test
    fun `and then shows the page beside it`() {
        val page = page("Bone")

        assertEquals(
            PaneSplit(detail = page),
            PaneSplit.of(library(page), StoryArcWindowClass.EXPANDED),
        )
    }

    @Test
    fun `every width above expanded does the same`() {
        val page = page("Bone")

        assertEquals(
            PaneSplit(detail = page),
            PaneSplit.of(library(page), StoryArcWindowClass.LARGE),
        )
        assertEquals(
            PaneSplit(detail = page),
            PaneSplit.of(library(page), StoryArcWindowClass.EXTRA_LARGE),
        )
    }

    @Test
    fun `only the library splits`() {
        // Home and Downloads are single surfaces. A shelf and the page of a book on it are
        // the one list-and-detail pair in this app, and inventing a second would be the
        // scaffold deciding the information architecture.
        assertNull(PaneSplit.of(AppNavigation(), StoryArcWindowClass.EXTRA_LARGE))
        assertNull(
            PaneSplit.of(
                AppNavigation().select(AppDestination.DOWNLOADS),
                StoryArcWindowClass.EXTRA_LARGE,
            ),
        )
    }

    @Test
    fun `a screen that is not a publication page takes the whole window`() {
        // Settings, a server browser, a source that is not answering: places in their own
        // right, drawn the same on a tablet as on a phone.
        assertNull(PaneSplit.of(library(Screen.Settings()), StoryArcWindowClass.EXTRA_LARGE))
        assertNull(PaneSplit.of(library(Screen.Shelves), StoryArcWindowClass.EXTRA_LARGE))
        assertNull(
            PaneSplit.of(
                library(Screen.Collection(UUID.randomUUID())),
                StoryArcWindowClass.EXTRA_LARGE,
            ),
        )
    }

    @Test
    fun `and so does a page reached from another page`() {
        // A cover leads to a page and a page's series shelf leads to another; two of them
        // deep, the reader is walking a path rather than looking at one shelf, and the shelf
        // that would be drawn beside them is no longer the one they came from.
        assertNull(
            PaneSplit.of(library(page("Bone"), page("Bone 2")), StoryArcWindowClass.EXTRA_LARGE),
        )
    }

    @Test
    fun `the shelf is named the same in one pane as in one column`() {
        // What stops a tablet reader losing their scroll position the moment they open a
        // cover: both layouts ask the state holder for the same position.
        assertEquals(AppNavigation().select(AppDestination.LIBRARY).stateKey, PaneSplit.listPaneKey)
    }
}
