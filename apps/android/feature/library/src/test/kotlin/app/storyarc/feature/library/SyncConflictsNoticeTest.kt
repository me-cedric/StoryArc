package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `library-sync` task 5.4: what a library sync found reaches the notice the library screen draws
 * (D3). One title names both positions, several give a count and Show, and none shows nothing.
 * iOS's `RefreshConflictsTests` makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class SyncConflictsNoticeTest {

    @get:Rule
    val compose = createComposeRule()

    @After
    fun clear() {
        RefreshConflicts.clear()
    }

    private fun synced(path: String, kept: Int, discarded: Int) = ProgressPull.Conflict(
        resolved = ReadingProgress(
            identity = PublicationIdentity(normalizedPath = path),
            position = ReadingPosition.Page(kept, 20),
            updatedAtEpochMillis = 0,
        ),
        discarded = ReadingPosition.Page(discarded, 20),
    )

    private fun show() {
        compose.setContent { StoryArcTheme { RefreshConflictNotice(viewModel = null) } }
    }

    @Test
    fun `one sync conflict names its file and both positions`() {
        SyncConflicts.report(listOf(synced("/Books/Marsh Auburn.cbz", kept = 11, discarded = 4)))
        show()

        compose.onNodeWithText("“Marsh Auburn”", substring = true).assertExists()
        compose.onNodeWithText("page 12 of 20", substring = true).assertExists()
        compose.onNodeWithText("page 5 of 20", substring = true).assertExists()
        compose.onNodeWithText("Show").assertDoesNotExist()
    }

    @Test
    fun `several sync conflicts give a count and a list naming each title`() {
        SyncConflicts.report(
            listOf(
                synced("content://tree/primary%3ABooks%2FTide.cbz", kept = 7, discarded = 2),
                synced("/Books/Night Market.epub", kept = 5, discarded = 1),
            ),
        )
        show()

        compose.onNodeWithText("2 titles", substring = true).assertExists()
        compose.onNodeWithText("Show").performClick()
        compose.onNodeWithText("Tide: kept at page 8 of 20, not page 3 of 20.").assertExists()
        compose.onNodeWithText("Night Market: kept at page 6 of 20, not page 2 of 20.").assertExists()
    }

    @Test
    fun `a sync with no conflict shows no notice`() {
        SyncConflicts.report(emptyList())
        show()

        assertTrue(RefreshConflicts.conflicts.value.isEmpty())
        compose.onNodeWithText("Read in two places").assertDoesNotExist()
    }
}
