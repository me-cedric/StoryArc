package app.storyarc.feature.library

import android.app.Application
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * The screen that offers the cover choice, and the view model call the choice reaches.
 *
 * The picker answering its own questions proves nothing about whether a reader can open it.
 * [ShelfCoverChoice] and `Shelves.settingCover` were tested for weeks while no screen called
 * either, so a symbol search looked convincing and the clause was still unreachable. This
 * composes [CollectionDetailScreen] itself and asks the semantics tree for the control.
 *
 * iOS's `ShelfCoverMenuTests` walks the built value tree of the same screen, case for case.
 *
 * Robolectric, for [ShelfLifecycleTest]'s reason: [LibraryViewModel] takes an `Application`.
 * No store is passed, so nothing here writes to the machine the test runs on.
 */
@RunWith(RobolectricTestRunner::class)
// 34 for the reason `ShelfDeletionDialogTest` gives: Robolectric has no image for 37.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class ShelfCoverMenuTest {

    @get:Rule
    val compose = createComposeRule()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** A view model holding one collection, with the members this case needs. */
    private fun model(holding: Set<String>): Pair<LibraryViewModel, UUID> {
        val viewModel = LibraryViewModel(application)
        viewModel.createCollection("Image Comics")
        val id = viewModel.shelves.value.collections.first().id
        if (holding.isNotEmpty()) viewModel.addToCollection(holding, id)
        return viewModel to id
    }

    private fun show(viewModel: LibraryViewModel, id: UUID): String {
        var name = ""
        compose.setContent {
            name = stringResource(R.string.shelves_cover)
            StoryArcTheme {
                CollectionDetailScreen(viewModel = viewModel, id = id, onOpen = {}, onBack = {})
            }
        }
        compose.waitForIdle()
        return name
    }

    @Test
    fun `a collection holding something offers the cover choice`() {
        val (viewModel, id) = model(holding = setOf("a", "b"))

        val name = show(viewModel, id)

        compose.onNodeWithContentDescription(name).assertIsDisplayed()
    }

    @Test
    fun `a collection holding nothing does not offer it`() {
        val (viewModel, id) = model(holding = emptySet())

        val name = show(viewModel, id)

        compose.onNodeWithContentDescription(name).assertDoesNotExist()
    }

    /** Choosing reaches the view model, and the view model reaches `Shelves`. */
    @Test
    fun `the chosen cover is the one the collection then wears`() {
        val (viewModel, id) = model(holding = setOf("a", "b"))

        viewModel.setCollectionCover("b", id)

        val collection = viewModel.shelves.value.collections.first()
        assertEquals("b", collection.coverMemberId)
        assertEquals(ShelfCoverOption.Member("b"), ShelfCoverChoice.chosen(collection))
    }
}
