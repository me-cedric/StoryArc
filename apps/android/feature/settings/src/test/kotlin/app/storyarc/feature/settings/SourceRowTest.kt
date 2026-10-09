package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.geometry.Offset
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.ImportedCopies
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `close-the-audited-gaps` 27.3, decision O29: a row of "Your libraries" carries one overflow
 * menu and a drag handle, not four icon buttons. iOS asks the same of its swipe actions.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class SourceRowTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val first = source("Attic NAS")
    private val middle = source("Reading room")
    private val last = source("Phone folder")
    private val sources = listOf(first, middle, last)

    private val reordered = mutableListOf<Pair<String, Boolean>>()
    private val removed = mutableListOf<String>()

    private fun source(name: String, id: java.util.UUID = java.util.UUID.randomUUID()) = Source(
        id = id,
        displayName = name,
        kind = SourceKind.NETWORK_SHARE,
        state = SourceConnectionState.Connected,
    )

    private fun show(list: List<Source> = sources) {
        compose.setContent {
            StoryArcTheme(useDynamicColor = false, natural = false) {
                SourcesGroup(
                    sources = list,
                    itemCount = { 3 },
                    diagnose = { s -> SourceDiagnosis.of(s, itemCount = 3, downloads = emptyList()) },
                    onRemove = { removed += it.displayName },
                    onRename = { _, _ -> },
                    onReorder = { s, later -> reordered += s.displayName to later },
                )
            }
        }
        compose.waitForIdle()
    }

    private fun more(name: String) = context.getString(R.string.sources_menu_more, name)

    private fun openMenu(name: String) {
        compose.onNodeWithContentDescription(more(name)).performClick()
        compose.waitForIdle()
    }

    @Test
    fun `each row has one overflow button and none of the four icon buttons`() {
        show()

        for (name in listOf(first, middle, last).map { it.displayName }) {
            compose.onNodeWithContentDescription(more(name)).assertIsDisplayed()
            for (gone in listOf(
                context.getString(R.string.sources_remove_action, name),
                context.getString(R.string.sources_rename_action, name),
                context.getString(R.string.sources_move_earlier, name),
                context.getString(R.string.sources_move_later, name),
            )) {
                assertTrue(
                    "\"$gone\" is still an icon button on the row",
                    compose.onAllNodesWithContentDescription(gone).fetchSemanticsNodes().isEmpty(),
                )
            }
        }
    }

    @Test
    fun `the menu lists the moves and Rename, then Remove last`() {
        show()
        openMenu(middle.displayName)

        val top = listOf(
            R.string.sources_menu_move_up,
            R.string.sources_menu_move_down,
            R.string.sources_menu_rename,
            R.string.sources_remove,
        ).map { compose.onNodeWithText(context.getString(it)).getBoundsInRoot().top.value }

        assertEquals("the menu order is not Move up, Move down, Rename, Remove", top.sorted(), top)
    }

    @Test
    fun `the first row cannot move up and the last cannot move down`() {
        show()
        openMenu(first.displayName)
        compose.onNodeWithText(context.getString(R.string.sources_menu_move_up)).assertIsNotEnabled()
        compose.onNodeWithText(context.getString(R.string.sources_menu_move_down)).performClick()
        assertEquals(listOf(first.displayName to true), reordered)
    }

    @Test
    fun `Move up on a middle row moves it one place earlier`() {
        show()
        openMenu(middle.displayName)
        compose.onNodeWithText(context.getString(R.string.sources_menu_move_up)).performClick()
        assertEquals(listOf(middle.displayName to false), reordered)
    }

    @Test
    fun `Remove from the menu asks first and removes only on confirmation`() {
        show()
        openMenu(middle.displayName)
        compose.onNodeWithText(context.getString(R.string.sources_remove)).performClick()
        compose.waitForIdle()

        compose.onNodeWithText(context.getString(R.string.sources_remove_title, middle.displayName)).assertIsDisplayed()
        assertTrue("removed before the confirmation", removed.isEmpty())

        compose.onNodeWithText(context.getString(R.string.sources_remove)).performClick()
        compose.waitForIdle()
        assertEquals(listOf(middle.displayName), removed)
    }

    @Test
    fun `On this device has no Remove in its menu`() {
        val device = source("On this device", ImportedCopies.SOURCE_ID)
        show(listOf(first, device))
        openMenu(device.displayName)

        assertTrue(
            compose.onAllNodesWithText(context.getString(R.string.sources_remove)).fetchSemanticsNodes().isEmpty(),
        )
        compose.onNodeWithText(context.getString(R.string.sources_menu_rename)).assertIsDisplayed()
    }

    @Test
    fun `TalkBack reads the four actions off the row`() {
        show()
        val row = compose.onNode(
            hasClickAction() and hasText(middle.displayName),
        ).fetchSemanticsNode()
        val labels = row.config.getOrNull(SemanticsActions.CustomActions).orEmpty().map { it.label }

        assertEquals(
            listOf(
                context.getString(R.string.sources_move_earlier, middle.displayName),
                context.getString(R.string.sources_move_later, middle.displayName),
                context.getString(R.string.sources_rename_action, middle.displayName),
                context.getString(R.string.sources_remove_action, middle.displayName),
            ),
            labels,
        )
    }

    @Test
    fun `dragging the handle down moves the row later and never earlier`() {
        show()
        compose.onNodeWithTag(dragHandleTag(first), useUnmergedTree = true).performTouchInput {
            down(center)
            repeat(10) { moveBy(Offset(0f, 40f)) }
            up()
        }
        compose.waitForIdle()

        assertTrue("the drag moved nothing", reordered.isNotEmpty())
        assertTrue(reordered.all { it == first.displayName to true })
    }

    @Test
    fun `a single row has no handle and no move items`() {
        show(listOf(first))
        assertTrue(compose.onAllNodesWithTag(dragHandleTag(first), useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        openMenu(first.displayName)
        assertTrue(
            compose.onAllNodesWithText(context.getString(R.string.sources_menu_move_up)).fetchSemanticsNodes().isEmpty(),
        )
    }

    @Test
    fun `the rule says which moves a row has`() {
        val other = java.util.UUID.randomUUID()
        assertFalse(sourceRowActions(0, 1, other).canReorder)
        assertFalse(sourceRowActions(0, 3, other).canMoveEarlier)
        assertTrue(sourceRowActions(0, 3, other).canMoveLater)
        assertTrue(sourceRowActions(2, 3, other).canMoveEarlier)
        assertFalse(sourceRowActions(2, 3, other).canMoveLater)
        assertFalse(sourceRowActions(1, 3, ImportedCopies.SOURCE_ID).canRemove)
        assertTrue(sourceRowActions(1, 3, other).canRemove)
    }

    private fun dragHandleTag(source: Source) = sourceDragHandleTag(source)
}
