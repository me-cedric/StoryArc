package app.storyarc.feature.library

import android.app.Application
import android.content.Context
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Every control on the library's chrome names itself, and the occasional ones share one menu.
 *
 * `library-browsing`, two scenarios of *Presentation*. *A control that stands alone carries a
 * name*: "every one of them names itself to assistive technology whatever it draws". *The
 * controls that change the view are grouped*: the choices are "reached through named menus
 * rather than as separate unlabelled buttons", and only a control that changes *mode* may stand
 * on its own. `named-failures-and-quieter-chrome` was archived with the descriptions in place —
 * `AddSourceMenu`, `LibraryOverflowMenu`, `LayoutToggle` — and nothing pinning any of them.
 *
 * **The semantics tree is asked, not the source.** A test reading the files for the word
 * `contentDescription` would pass on a description attached to the wrong node, or to a node
 * that is no longer a control. Robolectric composes the real bar, so what TalkBack would be
 * handed can be asked for directly: which nodes can be pressed, and whether each of them says
 * what it is. The bar had eight action icons once and no room for its title; the number of
 * things that can be pressed before any menu opens is what stops that coming back.
 *
 * Reachable rather than merely present: a row inside a `DropdownMenu` is composed only while
 * the menu is open, so the grouped controls are asserted absent before the press and present
 * after it, together — which is what "grouped" looks like in a tree.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LibraryControlsAreNamedTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun string(id: Int, vararg arguments: Any): String = context.getString(id, *arguments)

    /** The bar with every way in offered, unless a test withholds the occasional ones. */
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun Bar(
        onSelect: (() -> Unit)? = {},
        onOpenShelves: (() -> Unit)? = {},
        onOpenSettings: (() -> Unit)? = {},
    ) {
        LibraryTopBar(
            scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(),
            onAddFolder = {},
            onAddCatalogue = {},
            onAddKavita = {},
            onAddShare = {},
            onImport = {},
            onSelect = onSelect,
            onOpenShelves = onOpenShelves,
            onOpenSettings = onOpenSettings,
        )
    }

    /** The controls under the bar, over a view model with nothing in it. */
    @Composable
    private fun Controls(layout: LibraryLayout) {
        val application = ApplicationProvider.getApplicationContext<Application>()
        LibraryControls(
            query = LibraryQuery(),
            registry = SourceRegistry(),
            layout = layout,
            availability = LibraryAvailability.EVERYTHING,
            downloads = DownloadFilter.EITHER,
            onAvailabilityChange = {},
            onQueryChange = {},
            onDownloadsChange = {},
            onLayoutChange = {},
            onClearFilters = {},
            viewModel = LibraryViewModel(application),
        )
    }

    /**
     * Every node that can be pressed, with the ones that say nothing about themselves.
     *
     * A control is named by a content description or by the text merged into it; a chip is
     * the second kind and an icon button the first. One that is neither is a glyph a reader
     * has to press to find out what it does.
     */
    private fun pressable(): Pair<Int, List<String>> {
        val nodes = compose.onAllNodes(hasClickAction()).fetchSemanticsNodes()
        val nameless = nodes.filter { node ->
            val described = node.config.getOrNull(SemanticsProperties.ContentDescription)
                ?.any { it.isNotBlank() } == true
            val worded = node.config.getOrNull(SemanticsProperties.Text)
                ?.any { it.text.isNotBlank() } == true
            !described && !worded
        }
        return nodes.size to nameless.map { "node ${it.id} at ${it.boundsInRoot}" }
    }

    @Test
    fun `the two controls that stand alone in the bar both say what they are`() {
        compose.setContent { StoryArcTheme { Bar() } }

        compose.onNodeWithContentDescription(string(R.string.library_add_source)).assertHasClickAction()
        compose.onNodeWithContentDescription(string(R.string.library_more)).assertHasClickAction()

        // Two, and named. More than two is the row of icons coming back; a nameless one is a
        // control a reader has to press to identify.
        val (count, nameless) = pressable()
        assertEquals("the bar holds more standalone controls than the two it is allowed", 2, count)
        assertTrue("controls in the bar say nothing about themselves: $nameless", nameless.isEmpty())
    }

    @Test
    fun `what a reader touches once a week is behind one named menu, each row named`() {
        compose.setContent { StoryArcTheme { Bar() } }
        val select = string(R.string.library_select)
        val shelves = string(R.string.shelves_title)
        val settings = string(R.string.library_settings)

        // Not on the bar: none of the three is reachable before the menu opens.
        compose.onNodeWithText(select).assertDoesNotExist()
        compose.onNodeWithText(shelves).assertDoesNotExist()
        compose.onNodeWithText(settings).assertDoesNotExist()

        compose.onNodeWithContentDescription(string(R.string.library_more)).performClick()

        // One press, all three, each a named control of its own.
        compose.onNodeWithText(select).assertIsDisplayed().assertHasClickAction()
        compose.onNodeWithText(shelves).assertIsDisplayed().assertHasClickAction()
        compose.onNodeWithText(settings).assertIsDisplayed().assertHasClickAction()
        val (count, nameless) = pressable()
        assertEquals("the open menu holds something other than its three rows", 2 + 3, count)
        assertTrue("a menu row says nothing about itself: $nameless", nameless.isEmpty())
    }

    @Test
    fun `the ways to add a source share one button and are named inside it`() {
        compose.setContent { StoryArcTheme { Bar() } }
        val kinds = listOf(
            R.string.library_add_folder,
            R.string.library_import,
            R.string.catalogue_title,
            R.string.kavita_title,
            R.string.smb_title,
        ).map(::string)

        kinds.forEach { compose.onNodeWithText(it).assertDoesNotExist() }
        compose.onNodeWithContentDescription(string(R.string.library_add_source)).performClick()
        kinds.forEach { compose.onNodeWithText(it).assertIsDisplayed().assertHasClickAction() }

        val (_, nameless) = pressable()
        assertTrue("a way to add a source says nothing about itself: $nameless", nameless.isEmpty())
    }

    @Test
    fun `a bar with nothing occasional to offer draws no menu button`() {
        compose.setContent {
            StoryArcTheme { Bar(onSelect = null, onOpenShelves = null, onOpenSettings = null) }
        }

        // Absent rather than empty: a `⋮` that opens nothing is worse than no `⋮`.
        compose.onNodeWithContentDescription(string(R.string.library_more)).assertDoesNotExist()
        compose.onNodeWithContentDescription(string(R.string.library_add_source)).assertHasClickAction()
        assertEquals(1, pressable().first)
    }

    @Test
    fun `the controls under the bar name themselves, the toggle by the layout it would switch to`() {
        compose.setContent { StoryArcTheme { Controls(layout = LibraryLayout.GRID) } }

        // The three choices are chips that say what they are doing in a word.
        compose.onNodeWithText(string(R.string.source_on_this_device)).assertHasClickAction()
        compose.onNodeWithText(
            string(R.string.library_sort_chip, string(LibrarySort.TITLE.labelRes)),
        ).assertHasClickAction()
        compose.onNodeWithText(string(R.string.library_filter)).assertHasClickAction()
        // The toggle draws the layout it would switch *to*, and is named for it: a grid offers
        // the list.
        compose.onNodeWithContentDescription(string(R.string.library_layout_list)).assertHasClickAction()
        compose.onNodeWithContentDescription(string(R.string.library_layout_grid)).assertDoesNotExist()

        val (count, nameless) = pressable()
        assertEquals("the row holds more controls than its four", 4, count)
        assertTrue("controls under the bar say nothing about themselves: $nameless", nameless.isEmpty())
    }

    @Test
    fun `a list offers the grid, by name`() {
        compose.setContent { StoryArcTheme { Controls(layout = LibraryLayout.LIST) } }

        // The other half of "whatever it draws": the glyph changed, and so did the name.
        compose.onNodeWithContentDescription(string(R.string.library_layout_grid)).assertHasClickAction()
        compose.onNodeWithContentDescription(string(R.string.library_layout_list)).assertDoesNotExist()
        assertTrue(pressable().second.isEmpty())
    }
}
