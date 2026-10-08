package app.storyarc.feature.library

import android.content.Context
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `close-the-audited-gaps` 24.6: the A to Z rail is one control.
 *
 * Every test drives the rail the way a reader does: a finger down on it, a drag along it, or
 * TalkBack's own slider and named actions. iOS's `LibraryRailTests`, `HitRegionTests` and
 * `SweepLibraryTests.testTheIndexIsOneScrubber` answer the same questions.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class IndexRailIsOperableTest {

    @get:Rule
    val compose = createComposeRule()

    private fun string(id: Int, vararg args: Any): String =
        ApplicationProvider.getApplicationContext<Context>().getString(id, *args)

    private val entries = listOf(RailEntry("A", "one"), RailEntry("S", "two"), RailEntry("#", "three"))

    private val alphabet = ('A'..'Z').map { RailEntry(it.toString(), it.toString()) }

    private val rail get() = compose.onNodeWithContentDescription(string(R.string.library_index))

    private fun show(shown: List<RailEntry>, chosen: MutableList<String>) {
        compose.setContent {
            StoryArcTheme { IndexRail(entries = shown, onChoose = { chosen += it.label }) }
        }
    }

    /** A finger down at the top of the rail, dragged to [to] of its height in steps of 2 px. */
    private fun SemanticsNodeInteraction.drag(from: Float = 0f, to: Float = 1f) {
        performTouchInput {
            val start = from * height
            val end = to * height
            val direction = if (end >= start) 1f else -1f
            down(Offset(width / 2f, start))
            var y = start
            while ((end - y) * direction > 0f) {
                y += 2f * direction
                moveTo(Offset(width / 2f, if (direction > 0f) minOf(y, end) else maxOf(y, end)))
            }
            up()
        }
    }

    @Test
    fun `the rail is one named node that nothing else on it can be pressed`() {
        show(entries, mutableListOf())

        rail.assertExists()
        assertEquals(0, compose.onAllNodes(hasClickAction()).fetchSemanticsNodes().size)
    }

    @Test
    fun `the rail is a target of 48 dp or more`() {
        show(alphabet, mutableListOf())

        rail.assertTouchTargetIsAtLeast()
    }

    @Test
    fun `a tap on the rail chooses the letter under the finger`() {
        val chosen = mutableListOf<String>()
        show(entries, chosen)

        // Three letters of 24 dp between 8 dp of padding: the middle of the rail is the middle one.
        rail.performTouchInput { click(Offset(width / 2f, height / 2f)) }

        assertEquals(listOf("S"), chosen)
    }

    @Test
    fun `a drag down the whole rail chooses every letter, in order, once each`() {
        val chosen = mutableListOf<String>()
        show(alphabet, chosen)

        rail.drag()

        assertEquals(alphabet.map { it.label }, chosen)
    }

    @Test
    fun `a drag back up chooses the letters in reverse`() {
        val chosen = mutableListOf<String>()
        show(alphabet, chosen)

        rail.drag(from = 1f, to = 0f)

        assertEquals(alphabet.map { it.label }.reversed(), chosen)
    }

    @Test
    fun `a letter is chosen once while the finger stays on it`() {
        val chosen = mutableListOf<String>()
        show(entries, chosen)

        rail.performTouchInput {
            down(Offset(width / 2f, height / 2f))
            moveBy(Offset(0f, 3f))
            moveBy(Offset(0f, -3f))
            up()
        }

        assertEquals(listOf("S"), chosen)
    }

    @Config(sdk = [34], qualifiers = "w891dp-h180dp")
    @Test
    fun `every letter is reachable when the window is shorter than the alphabet`() {
        val chosen = mutableListOf<String>()
        show(alphabet, chosen)

        rail.drag()

        assertEquals(alphabet.map { it.label }, chosen)
    }

    @Test
    fun `each new letter plays one tick`() {
        val ticks = mutableListOf<Int>()
        compose.setContent {
            val view = remember {
                object : View(ApplicationProvider.getApplicationContext<Context>()) {
                    override fun performHapticFeedback(feedbackConstant: Int): Boolean {
                        ticks += feedbackConstant
                        return true
                    }
                }
            }
            CompositionLocalProvider(LocalView provides view) {
                StoryArcTheme { IndexRail(entries = alphabet, onChoose = {}) }
            }
        }

        rail.drag()

        assertEquals(List(alphabet.size) { HapticFeedbackConstants.TEXT_HANDLE_MOVE }, ticks)
    }

    @Test
    fun `the rail is a slider that steps to the next letter and says which one it is on`() {
        val chosen = mutableListOf<String>()
        show(entries, chosen)

        rail.performSemanticsAction(SemanticsActions.SetProgress) { it(1f) }

        assertEquals(listOf("S"), chosen)
        val state = rail.fetchSemanticsNode().config[SemanticsProperties.StateDescription]
        assertEquals("S", state)
    }

    @Test
    fun `every letter is also a named action that goes there`() {
        val chosen = mutableListOf<String>()
        show(entries, chosen)

        val actions = rail.fetchSemanticsNode().config[SemanticsActions.CustomActions]

        assertEquals(entries.map { string(R.string.library_index_jump, it.label) }, actions.map { it.label })
        compose.runOnUiThread { actions.first { it.label == string(R.string.library_index_jump, "S") }.action() }
        assertEquals(listOf("S"), chosen)
    }

    @Test
    fun `an empty index draws nothing that can be pressed`() {
        compose.setContent { StoryArcTheme { IndexRail(entries = emptyList(), onChoose = {}) } }

        assertEquals(0, compose.onAllNodes(hasClickAction()).fetchSemanticsNodes().size)
        assertTrue(
            compose.onAllNodes(hasContentDescription(string(R.string.library_index))).fetchSemanticsNodes().isEmpty(),
        )
    }
}
