package app.storyarc.feature.library

import android.app.Application
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A publication inside a series offers the same menu it offers everywhere else.
 *
 * `library-browsing`'s *A publication's actions wherever it is drawn* asks for one menu on
 * every surface that draws a publication. This screen drew the library's own [CoverGrid] and
 * passed it no actions, so a reader who opened a series met the only cell in the app that
 * answered a long press with nothing -- and the cell looks identical to the one in the grid
 * one destination back, which is what makes the silence read as a broken app rather than as a
 * screen without the feature.
 *
 * The grid is asked by composing the screen, not the grid: [ShelfCoverMenuTest] gives the
 * reason, and it applies in full here -- the rows the menu draws were tested for as long as
 * nothing on this screen opened one.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives. Robolectric because
 * [LibraryViewModel] takes an `Application`; no store is passed, so nothing here writes to the
 * machine the test runs on.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// 34 for the reason `ShelfDeletionDialogTest` gives: Robolectric has no image for 37.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class SeriesShelfOffersTheMenuTest {

    @get:Rule
    val compose = createComposeRule()

    private fun issue(title: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = "Lantern",
        origin = MetadataOrigin.EMBEDDED,
    )

    private fun show(): LibraryViewModel {
        val viewModel = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
        viewModel.adopt(issue("Lantern #1"), sourceId = null)
        viewModel.adopt(issue("Lantern #2"), sourceId = null)
        compose.setContent {
            StoryArcTheme {
                SeriesShelfScreen(
                    name = "Lantern",
                    viewModel = viewModel,
                    onOpen = {},
                    onBack = {},
                )
            }
        }
        compose.waitForIdle()
        return viewModel
    }

    @Test
    fun `holding an issue in a series opens the publication menu`() {
        show()

        compose.onNodeWithText("Lantern #1").performTouchInput { longClick() }

        compose.onNodeWithText("Open").assertExists()
        compose.onNodeWithText("Mark as read").assertExists()
        compose.onNodeWithText("Add to…").assertExists()
        compose.onNodeWithText("Show details").assertExists()
    }

    /**
     * A series is not a shelf the reader assembled, so there is nothing to leave. The row is
     * withheld rather than drawn dead, which is the rule every other control on this screen
     * follows.
     */
    @Test
    fun `the menu on a series offers no way to leave the shelf`() {
        show()

        compose.onNodeWithText("Lantern #1").performTouchInput { longClick() }

        compose.onNodeWithText("Remove from this shelf").assertDoesNotExist()
    }
}
