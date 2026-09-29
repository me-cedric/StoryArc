package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * D3, drawn: one conflict names both positions in the dialog, and several open a list that
 * names both positions for each title.
 *
 * `sdk = [34]` for the reason `KavitaCardFactsTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class SyncConflictDialogTest {

    @get:Rule
    val compose = createComposeRule()

    private fun conflict(title: String, kept: Int, discarded: Int) = KavitaConflict(
        title = title,
        resolved = ReadingProgress(
            identity = PublicationIdentity(normalizedPath = "/$title.cbz"),
            position = ReadingPosition.Page(kept, 20),
            updatedAtEpochMillis = 0,
        ),
        discarded = ReadingPosition.Page(discarded, 20),
    )

    private fun show(conflicts: List<KavitaConflict>) {
        compose.setContent {
            StoryArcTheme { SyncConflictNotice(conflicts = conflicts, onKeep = {}, onTake = {}) }
        }
    }

    @Test
    fun `one conflict names its title and both positions`() {
        show(listOf(conflict("Marsh Auburn", kept = 11, discarded = 4)))

        compose.onNodeWithText("Marsh Auburn", substring = true).assertExists()
        compose.onNodeWithText("page 12 of 20", substring = true).assertExists()
        compose.onNodeWithText("page 5 of 20", substring = true).assertExists()
    }

    @Test
    fun `several conflicts open a list naming both positions for each title`() {
        show(listOf(conflict("Marsh Auburn", kept = 11, discarded = 4), conflict("Tide", kept = 7, discarded = 2)))

        compose.onNodeWithText("Show").performClick()

        compose.onNodeWithText("Marsh Auburn: kept at page 12 of 20, not page 5 of 20.").assertExists()
        compose.onNodeWithText("Tide: kept at page 8 of 20, not page 3 of 20.").assertExists()
    }
}
