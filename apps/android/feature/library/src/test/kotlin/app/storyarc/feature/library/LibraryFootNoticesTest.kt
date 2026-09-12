package app.storyarc.feature.library

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * What the foot of the shelf says, and what the reader can do about it.
 *
 * [NeverReachedTest] asserts the rule without a screen. This asserts the other half: that a
 * source the library has never read reaches a composable, that the composable names it, and
 * that the action beside it asks the sources again. A rule nothing draws and a drawing
 * nothing decides are the two ways this can be wrong.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h1200dp")
class LibraryFootNoticesTest {

    @get:Rule
    val compose = createComposeRule()

    private val unread = Source(
        displayName = "Attic NAS",
        kind = SourceKind.KAVITA_SERVER,
        state = SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        locator = "https://x.invalid",
    )

    private fun show(
        folders: List<String> = emptyList(),
        sources: List<Source> = emptyList(),
        onRepick: () -> Unit = {},
        onRetry: () -> Unit = {},
    ) {
        compose.setContent {
            StoryArcTheme {
                LibraryFootNotices(
                    unavailableFolders = folders,
                    sources = sources,
                    onRepickFolder = onRepick,
                    onRetrySources = onRetry,
                )
            }
        }
    }

    @Test
    fun `a source that has never been reached is named`() {
        show(sources = listOf(unread))

        // The name is what the shelf could not say before. The count in
        // `library_still_being_read` names nobody, and so does `library_pending_body`.
        compose.onNodeWithText("Attic NAS", substring = true).assertIsDisplayed()
    }

    @Test
    fun `the line offers to try again, and that asks the sources`() {
        var asked = 0
        show(sources = listOf(unread), onRetry = { asked += 1 })

        compose.onNodeWithText("Try again").performClick()

        assertEquals(1, asked)
    }

    @Test
    fun `a source that has answered before puts no line at the foot of the shelf`() {
        // Away, not unread. The dimmed rows and the source's own screen carry that one.
        show(sources = listOf(unread.copy(lastSuccessfulSyncEpochMillis = 1_000L)))

        compose.onAllNodesWithText("Attic NAS", substring = true).assertCountEquals(0)
        compose.onAllNodesWithText("Try again").assertCountEquals(0)
    }

    @Test
    fun `a folder that can no longer be read outranks it, and only one line is drawn`() {
        show(folders = listOf("Comics"), sources = listOf(unread))

        compose.onNodeWithText("Comics", substring = true).assertIsDisplayed()
        compose.onAllNodesWithText("Attic NAS", substring = true).assertCountEquals(0)
    }
}
