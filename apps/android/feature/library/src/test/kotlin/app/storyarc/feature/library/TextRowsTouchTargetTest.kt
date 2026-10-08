package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.4 and 24.5 of `close-the-audited-gaps`: a line of text that is a button is a touch
 * target of 48 dp.
 *
 * Two lines were plain text with a click and a little padding: a recent search term drawn at
 * 24 sp, and the offer to search a Kavita server, drawn at 12 sp. Each was well under 48 dp
 * high. They are composed through the functions the search screen calls.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class TextRowsTouchTargetTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a recent search term is a 48 dp target`() {
        compose.setContent {
            StoryArcTheme {
                SearchAnswerList(
                    listing = SearchListing(term = ""),
                    recents = RecentSearches(listOf("akira", "bone")),
                    onUseRecent = {},
                    onClearRecents = {},
                    onOpenHeld = {},
                    onFollow = {},
                    onRetry = {},
                    scope = LibraryAvailability.EVERYTHING,
                    onScopeChange = {},
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithText("akira").assertTouchTargetIsAtLeast()
        compose.onNodeWithText("bone").assertTouchTargetIsAtLeast()
    }

    @Test
    fun `the offer to search the server is a 48 dp target`() {
        val server = Source(displayName = "Attic", kind = SourceKind.KAVITA_SERVER)
        compose.setContent {
            StoryArcTheme {
                KavitaSearchOffer(
                    registry = SourceRegistry(listOf(server)),
                    query = LibraryQuery(search = "saga", scope = LibraryScope.OneSource(server.id)),
                    onSearchOnServer = { _, _ -> },
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithText("Search “Attic” for this instead").assertTouchTargetIsAtLeast()
    }
}
