package app.storyarc

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The finished state of the player, over a book that ended on a failed part.
 *
 * Task 2.5, owner answer O12. `publication-formats`: a damaged audiobook "plays what it can and
 * states how much it could not … rather than interrupting playback". The count the live player
 * draws is gone once the session ends, so the screen it ends on states it too, in words and in
 * the count's own plural. A whole book states nothing.
 *
 * Robolectric with native graphics, for the reason `PlayerSemanticsTest` sets out.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37. A phone window, because it is the narrowest case.
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PlayerFinishedLossTest {

    @get:Rule
    val compose = createComposeRule()

    private fun finished(unplayedParts: Int) {
        compose.setContent {
            StoryArcTheme {
                PlayerFinishedScreen(
                    onBack = {},
                    next = null,
                    onOpenNext = {},
                    unplayedParts = unplayedParts,
                )
            }
        }
    }

    @Test
    fun `one part that could not be played is stated in the singular`() {
        finished(unplayedParts = 1)

        compose.onNodeWithText("1 part could not be played").assertIsDisplayed()
    }

    @Test
    fun `several parts are stated with their count`() {
        finished(unplayedParts = 3)

        compose.onNodeWithText("3 parts could not be played").assertIsDisplayed()
    }

    @Test
    fun `a whole book states no loss, and still says nothing is playing`() {
        finished(unplayedParts = 0)

        compose.onNodeWithText("Nothing is playing.").assertIsDisplayed()
        compose.onNodeWithText("could not be played", substring = true).assertDoesNotExist()
    }
}
