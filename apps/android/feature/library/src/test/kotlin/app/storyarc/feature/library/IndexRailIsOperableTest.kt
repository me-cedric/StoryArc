package app.storyarc.feature.library

import android.content.Context
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The index can be reached and operated without sight.
 *
 * `library-browsing`'s *The index without sight* scenario: the rail "is announced as one named
 * group", "each entry is announced as the letter it moves to", and "every entry can be reached
 * and operated without sight". A rail of single characters is exactly the control that passes a
 * visual review and fails a screen reader, so the semantics tree is asked rather than the
 * source — the same argument `LibraryControlsAreNamedTest` sets out at length.
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

    @Test
    fun `every letter is a button that says where it goes`() {
        val chosen = mutableListOf<String>()
        compose.setContent {
            StoryArcTheme { IndexRail(entries = entries, onChoose = { chosen += it.label }) }
        }

        for (entry in entries) {
            compose.onNodeWithContentDescription(string(R.string.library_index_jump, entry.label))
                .assertHasClickAction()
        }

        compose.onNodeWithContentDescription(string(R.string.library_index_jump, "S")).performClick()
        assertEquals(listOf("S"), chosen)
    }

    @Test
    fun `the rail is one named group, so it is announced once`() {
        compose.setContent { StoryArcTheme { IndexRail(entries = entries, onChoose = {}) } }

        compose.onNodeWithContentDescription(string(R.string.library_index)).assertExists()
    }

    /**
     * The other half of *A sort no letter describes*: absent, not drawn and inert. A rail that
     * composed an empty column would still take a strip of the shelf and still have to be
     * stepped over.
     */
    @Test
    fun `an empty index draws nothing that can be pressed`() {
        compose.setContent { StoryArcTheme { IndexRail(entries = emptyList(), onChoose = {}) } }

        assertEquals(0, compose.onAllNodes(hasClickAction()).fetchSemanticsNodes().size)
    }
}
