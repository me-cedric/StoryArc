package app.storyarc.feature.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ShelfEntry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * What one entry of a server's reading list says about how far the reader got.
 *
 * `collections-and-reading-lists` asks each entry to state its read state "in the same terms
 * the library uses for a publication". The library draws a badge for a part-read or finished
 * publication and draws nothing for an unread one, so an unread entry states itself to a
 * screen reader and not to the eye — which is why the unread case is asserted on the label
 * and not on a drawn string.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ServerListRowTest {

    @get:Rule
    val compose = createComposeRule()

    private fun row(read: Int, total: Int) {
        compose.setContent {
            StoryArcTheme {
                EntryRow(
                    row = ShelfEntry("3103", "Issue #43", false),
                    number = 1,
                    series = "Lantern Green",
                    progress = ServerListProgress.of(read, total),
                    cover = null,
                    isFetching = false,
                    canMoveUp = false,
                    canMoveDown = false,
                    onUp = {},
                    onDown = {},
                    onOpen = {},
                )
            }
        }
    }

    @Test
    fun `a part-read entry draws the position it reached`() {
        row(read = 11, total = 22)

        compose.onNodeWithText("50% read", substring = true).assertIsDisplayed()
    }

    @Test
    fun `a finished entry says so`() {
        row(read = 22, total = 22)

        compose.onNodeWithText("Finished", substring = true).assertIsDisplayed()
    }

    @Test
    fun `an unread entry draws no badge and says unread`() {
        row(read = 0, total = 22)

        compose.onNodeWithText("read", substring = true).assertDoesNotExist()
        compose.onNodeWithText("Finished", substring = true).assertDoesNotExist()
        compose.onNodeWithContentDescription("Unread", substring = true).assertExists()
    }

    @Test
    fun `an entry the server said nothing about claims nothing`() {
        row(read = 0, total = 0)

        compose.onNodeWithText("read", substring = true).assertDoesNotExist()
        compose.onNodeWithText("Finished", substring = true).assertDoesNotExist()
        compose.onNodeWithContentDescription("Unread", substring = true).assertDoesNotExist()
    }

    @Test
    fun `a row whose cover never arrives keeps its number, title and series`() {
        row(read = 11, total = 22)

        compose.onNodeWithText("Issue #43", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Lantern Green", substring = true).assertIsDisplayed()
        compose.onNodeWithText("1").assertIsDisplayed()
    }

    @Test
    fun `the list says how many of its entries are finished`() {
        compose.setContent {
            StoryArcTheme {
                ServerListSummary(ServerListProgress.Counted(finished = 2, of = 4))
            }
        }

        compose.onNodeWithText("2 of 4 read").assertIsDisplayed()
    }

    @Test
    fun `the row is one node naming its place, its title and its state`() {
        row(read = 22, total = 22)

        compose
            .onNodeWithContentDescription("1. Issue #43 Lantern Green Finished")
            .assertExists()
    }
}
