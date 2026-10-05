package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A suggestion on the search page offers the menu every other cover offers.
 *
 * The page draws Home's own [HomeShelfCell] so that a book looks the same one destination
 * apart -- and it looked the same and behaved differently: the cell was handed no actions, so
 * a long press here did nothing while the identical cell on Home opened the menu.
 * `library-browsing`'s *A publication's actions wherever it is drawn* names no exception for
 * a suggestion.
 *
 * The cell is found by its spoken description rather than by its title, for the reason
 * [SearchAtRestTest] gives: `homeCardSemantics` merges the card into one target.
 *
 * `GraphicsMode.NATIVE` and a real window size for the reason `ListOrderChipsWrapTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
class SearchSuggestionOffersTheMenuTest {

    @get:Rule
    val compose = createComposeRule()

    private val entry = HomeEntry(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/library/Tin Kingdom.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "Tin Kingdom",
            origin = MetadataOrigin.EMBEDDED,
        ),
        isReadableNow = true,
        pagesRemaining = null,
        fraction = 0.0,
        state = ReadState.UNREAD,
    )

    private fun show(actions: HomePublicationActions?) {
        compose.setContent {
            StoryArcTheme {
                SearchAtRest(
                    suggestions = SearchSuggestions(neverOpened = listOf(entry)),
                    scope = LibraryAvailability.EVERYTHING,
                    onScopeChange = {},
                    cover = { _, _ -> null },
                    onOpenPage = {},
                    onOpenFile = {},
                    onAddFolder = {},
                    onAddCatalogue = {},
                    onAddKavita = {},
                    onAddShare = {},
                    actions = actions,
                )
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun `holding a suggestion opens the publication menu`() {
        show(
            HomePublicationActions(
                onMark = { _, _ -> },
                onRestart = {},
                onAddToShelf = {},
                onDownload = {},
                onRemoveDownload = {},
            ),
        )

        compose.onNodeWithContentDescription("Tin Kingdom").performTouchInput { longClick() }

        compose.onNodeWithText("Open").assertExists()
        compose.onNodeWithText("Mark as read").assertExists()
        compose.onNodeWithText("Add to…").assertExists()
        compose.onNodeWithText("Show details").assertExists()
    }

    /** No menu at all for a caller with nowhere to send the actions, never a dead one. */
    @Test
    fun `a page wired to nothing draws no menu`() {
        show(actions = null)

        compose.onNodeWithContentDescription("Tin Kingdom").performTouchInput { longClick() }

        compose.onNodeWithText("Mark as read").assertDoesNotExist()
    }
}
