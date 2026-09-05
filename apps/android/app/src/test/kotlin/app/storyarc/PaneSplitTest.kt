package app.storyarc

import androidx.compose.runtime.saveable.SaverScope
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
    fun `an expanded window is two panes before a page is opened on it`() {
        // A split with nothing in its second pane, not the absence of a split.
        // `publication-detail` puts one sentence there rather than an empty rectangle, and
        // the shelf keeps one width for the whole visit instead of reflowing on the first
        // tap.
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

    // The resize path -- task 4.3.
    //
    // The cases above assert the two ends separately: a narrow window has no split, a wide
    // one does. Neither of them walks the *sequence*, which is the thing a reader actually
    // does -- drag a tablet's window narrow with a book open, and drag it back.

    @Test
    fun `narrowing a two-pane window to one keeps the page the reader was looking at`() {
        val open = library(page("Bone"))

        val wide = PaneSplit.of(open, StoryArcWindowClass.EXPANDED)
        val narrow = PaneSplit.of(open, StoryArcWindowClass.COMPACT)

        // Two panes, then one -- and the publication is the same value either side, because
        // `of` never writes to the navigation it is handed. The page is not "restored" on
        // the way back; it never left. That is the property, and it is why the split is a
        // pure read of the width rather than state of its own.
        assertEquals("Bone", wide?.detail?.publication?.displayTitle)
        assertNull(narrow)
        assertEquals(page("Bone"), open.current)
    }

    @Test
    fun `widening restores the second pane, with the same page in it`() {
        val open = library(page("Bone"))

        // Narrow, then wide again. Not `assertNotNull` and a fresh look: the same navigation
        // value, put through the whole round trip, has to produce a split equal to the one it
        // started with. A `PaneSplit` that had gone through a copy would compare unequal.
        val before = PaneSplit.of(open, StoryArcWindowClass.EXPANDED)
        PaneSplit.of(open, StoryArcWindowClass.COMPACT)
        val after = PaneSplit.of(open, StoryArcWindowClass.EXPANDED)

        assertEquals(before, after)
        assertEquals("Bone", after?.detail?.publication?.displayTitle)
    }

    @Test
    fun `the resize guarantee rests on the manifest, because the saver drops the path`() {
        // The one thing that weakens the by-construction argument, asserted rather than left
        // in a comment. `AppNavigation.Saver` persists the destination's **name** and nothing
        // else -- a live catalogue page, an open publication and a server address do not
        // belong in a saved-state bundle, and its own KDoc says so.
        //
        // So a resize keeps the open page only because `AndroidManifest.xml`'s
        // `configChanges` stops the activity being recreated at all. Any configuration change
        // outside that list rebuilds the activity, the saver runs, and the reader lands on
        // the Library destination at its root. That is a deliberate trade and a documented
        // one; what it is not is "the page always survives", and this is where the difference
        // is written down so a later reader does not conclude the stronger thing from the two
        // cases above.
        val open = library(page("Bone"))
        val saved = with(AppNavigation.Saver) { TestSaverScope.save(open) }
        val restored = AppNavigation.Saver.restore(requireNotNull(saved))

        assertEquals(AppDestination.LIBRARY, restored?.destination)
        assertNull("The saver kept the path; this test's premise is now wrong.", restored?.current)
        assertNull(PaneSplit.of(restored!!, StoryArcWindowClass.EXPANDED)?.detail)
    }

    /** What a `Saver` is handed at save time. Nothing here consults it. */
    private object TestSaverScope : SaverScope {
        override fun canBeSaved(value: Any): Boolean = true
    }
}
