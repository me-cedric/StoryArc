package app.storyarc.feature.settings

import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The byline names the handle, and it is the control that goes there.
 *
 * `settings-and-about` used to ask for the author's name and, separately, for a link to the
 * profile. The screen drew both, so two rows carried one fact and the row a reader looks at
 * first did nothing. The requirement now asks for one byline that is itself the control.
 *
 * Three claims, and the third is the one worth a test. A renamed string is caught by the
 * string checks; a byline that stops being clickable is caught by nothing, because a `Text`
 * and a `TextButton` draw almost the same row.
 *
 * The group is composed rather than read as text: a row left behind a comment satisfies a
 * text match and fails a reader. iOS answers the same claims in `AboutBylineTests.swift`,
 * over source text, because `swift test` runs on the host with no simulator and cannot
 * compose a view.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class AboutBylineTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the byline names the handle and not a legal name`() {
        compose.setContent { StoryArcTheme { AboutGroup() } }

        compose.onNodeWithText("By @me-cedric").assertExists()
        assertEquals(
            "the byline must not name a person the reader cannot look up",
            0,
            compose.onAllNodesWithText("By Cédric Meyer").fetchSemanticsNodes().size,
        )
    }

    @Test
    fun `the byline is the control that opens the profile`() {
        compose.setContent { StoryArcTheme { AboutGroup() } }

        compose.onNodeWithText("By @me-cedric").assertHasClickAction()
    }

    @Test
    fun `no second row goes to the same address`() {
        compose.setContent { StoryArcTheme { AboutGroup() } }

        assertEquals(
            "the byline is the way to the author, so the separate row must be gone",
            0,
            compose.onAllNodesWithText("The author on GitHub").fetchSemanticsNodes().size,
        )
    }
}
