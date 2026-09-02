package app.storyarc.feature.library

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The chrome a selection puts up on Android, which is a **contextual top app bar**.
 *
 * **It was a bottom slab, and the bottom is not Android's to spend.** `BulkActionBar` drew a
 * `Surface` of `surfaceRaised` across the foot of the shelf, holding a count, three
 * `IconButton`s and a *Done* — a straight translation of what iOS was doing, and iOS was
 * doing it wrong too. On Android the foot of the window already belongs to the navigation
 * bar, and `native-experience` asks each app to follow "that platform's current design
 * language": Material 3 Expressive's answer to a selection is the contextual top app bar —
 * a close affordance at the start, the count as the title, the actions as top-bar actions
 * with an overflow.
 *
 * **This diverges from iOS on purpose, and ADR-0001 is why it may.** iOS *hides* its tab bar
 * and puts a floating glass capsule where the tab bar was, because that is what Photos,
 * Files and Mail do. Android does the opposite: it never puts selection chrome at the bottom,
 * so its navigation bar is untouched for the whole mode. Two platforms, one requirement, two
 * idioms — which is the point of the ADR rather than an inconsistency to be reconciled.
 *
 * **Which actions are drawn as glyphs, and which is named.** *Download* and *Mark as read*
 * are icon actions: a downward arrow and a check are glyphs a reader already knows, and a
 * top app bar's action slot has no room for text at any width. *Add to…* is in the overflow
 * with its name visible — `PlaylistAdd` is exactly the sort of glyph the design review of
 * 2026-09-01 objected to, and the action opens a chooser rather than doing something, so a
 * named row leading to a sheet is the honest shape. Every one of the three carries a
 * `contentDescription` unconditionally, which is what the requirement asks for and what
 * these tests check.
 *
 * Compositions rather than source text: Robolectric composes real widgets here, so what a
 * reader is shown and what TalkBack is told can both be asked directly. iOS asserts its half
 * structurally in `BulkSelectionChromeTests`, because `swift test` has no window.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and none
// of the questions here has an API level in it.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class BulkSelectionChromeTest {

    @get:Rule
    val compose = createComposeRule()

    /** A selection holding [count] publications, in the mode. */
    private fun picking(count: Int): LibrarySelection {
        var selection = LibrarySelection().begin()
        for (index in 0 until count) selection = selection.toggle("p$index")
        return selection
    }

    /**
     * The count is the bar's title, at nought, at one and at many.
     *
     * Nought is worth its own case: the mode is entered before anything is picked, and a
     * title that only appeared on the first tap would leave the bar blank for the frame in
     * which a reader is deciding what the mode is. One and five are worth theirs because
     * `library_selected` is a plural in four languages, and a `stringResource` where a
     * `pluralStringResource` belongs reads correctly at five and wrongly at one.
     */
    @Test
    fun `the count is the title at nought, one and many`() {
        val counts = listOf(0, 1, 5)
        val expected = mutableMapOf<Int, String>()
        // One composition, driven by state: the rule accepts `setContent` once per test, and
        // a selection changing under the same bar is what a reader actually does anyway.
        val state = mutableStateOf(picking(0))
        compose.setContent {
            StoryArcTheme {
                for (count in counts) {
                    expected[count] =
                        pluralStringResource(R.plurals.library_selected, count, count)
                }
                LibrarySelectionTopBar(
                    selection = state.value,
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        for (count in counts) {
            state.value = picking(count)
            compose.waitForIdle()
            val says = expected.getValue(count)
            assertTrue("the count string for $count is empty", says.isNotBlank())
            compose.onNodeWithText(says).assertIsDisplayed()
        }
    }

    /**
     * Every control in the bar names itself to assistive technology, whatever it draws.
     *
     * `native-experience` asks that every control be reachable and named; a bare `Icon` with
     * a null description is a control TalkBack can only call "button". Four of them: the way
     * out, the two icon actions, and the overflow that holds the third.
     */
    @Test
    fun `every control names itself to assistive technology`() {
        var stopping = ""
        var download = ""
        var markRead = ""
        var more = ""
        compose.setContent {
            StoryArcTheme {
                stopping = stringResource(R.string.library_select_stop)
                download = stringResource(R.string.library_bulk_download)
                markRead = stringResource(R.string.library_mark_read)
                more = stringResource(R.string.library_more)
                LibrarySelectionTopBar(
                    selection = picking(2),
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        for (name in listOf(stopping, download, markRead, more)) {
            assertTrue("a control in the selection bar has no name", name.isNotBlank())
            compose.onNodeWithContentDescription(name).assertIsDisplayed()
        }
    }

    /**
     * And the one action whose glyph would lie is named in words a reader can see.
     *
     * *Add to…* opens a chooser and `PlaylistAdd` does not say so. It is an overflow row with
     * its name showing, which is the same shape [LibraryOverflowMenu] uses for everything the
     * library's own bar stopped spending an icon on.
     */
    @Test
    fun `the action that cannot be a glyph is named in the overflow`() {
        var addTo = ""
        var more = ""
        var opened = false
        compose.setContent {
            StoryArcTheme {
                addTo = stringResource(R.string.shelves_add_to)
                more = stringResource(R.string.library_more)
                LibrarySelectionTopBar(
                    selection = picking(2),
                    onSelectionChange = {},
                    onAddToShelf = { opened = true },
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(more).performClick()
        compose.waitForIdle()
        compose.onNodeWithText(addTo).assertIsDisplayed()

        compose.onNodeWithText(addTo).performClick()
        compose.waitForIdle()
        assertTrue("the named row does not reach the add-to sheet", opened)
    }

    /**
     * Nothing picked, nothing to do — and the controls say so rather than vanishing.
     *
     * Same answer as iOS, and for the same reason: chrome that appeared on the first pick
     * would arrive under a thumb that is mid-tap. The way out is not in that group — it is
     * the close affordance at the start of the bar, and it stays live throughout, because a
     * reader who picked nothing is exactly the reader who most needs to leave.
     */
    @Test
    fun `the actions are inert at nought picked and live above it`() {
        var download = ""
        var markRead = ""
        var more = ""
        var stopping = ""
        val state = mutableStateOf(picking(0))
        compose.setContent {
            StoryArcTheme {
                download = stringResource(R.string.library_bulk_download)
                markRead = stringResource(R.string.library_mark_read)
                more = stringResource(R.string.library_more)
                stopping = stringResource(R.string.library_select_stop)
                LibrarySelectionTopBar(
                    selection = state.value,
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        for (name in listOf(download, markRead, more)) {
            compose.onNodeWithContentDescription(name).assertIsNotEnabled()
        }
        compose.onNodeWithContentDescription(stopping).assertIsEnabled()

        state.value = picking(1)
        compose.waitForIdle()
        for (name in listOf(download, markRead, more)) {
            compose.onNodeWithContentDescription(name).assertIsEnabled()
        }
        compose.onNodeWithContentDescription(stopping).assertIsEnabled()
    }

    /**
     * Leaving the mode gives the shelf its own bar back, and gives back the picks with it.
     *
     * The bar cannot see the chrome it is replacing, so what is asserted here is the value it
     * hands back: a selection that is no longer active and no longer holding anything. The
     * screen swaps [LibraryTopBar] in on exactly that, and [BulkActions] holds the same two
     * properties for iOS in `LibrarySelectionTests`.
     */
    @Test
    fun `the close affordance leaves the mode and drops the picks`() {
        var handedBack: LibrarySelection? = null
        var stopping = ""
        compose.setContent {
            StoryArcTheme {
                stopping = stringResource(R.string.library_select_stop)
                LibrarySelectionTopBar(
                    selection = picking(3),
                    onSelectionChange = { handedBack = it },
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(stopping).performClick()
        compose.waitForIdle()

        val ended = requireNotNull(handedBack) { "the way out handed nothing back" }
        assertFalse("the shelf is still in selection mode", ended.isActive)
        assertEquals("the picks outlived the mode", 0, ended.ids.size)
    }

    /** The two icon actions reach their callbacks, so the bar is wired and not merely drawn. */
    @Test
    fun `the icon actions reach what they name`() {
        var downloaded = false
        var marked = false
        var download = ""
        var markRead = ""
        compose.setContent {
            StoryArcTheme {
                download = stringResource(R.string.library_bulk_download)
                markRead = stringResource(R.string.library_mark_read)
                LibrarySelectionTopBar(
                    selection = picking(2),
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = { downloaded = true },
                    onMarkRead = { marked = true },
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(download).performClick()
        compose.onNodeWithContentDescription(markRead).performClick()
        compose.waitForIdle()

        assertTrue("the download action is drawn and wired to nothing", downloaded)
        assertTrue("the mark-read action is drawn and wired to nothing", marked)
    }
}
