package app.storyarc.feature.library

import android.app.Application
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 7.13's own half of [ShelfCoverMenuTest]: the same three claims, for a reading list's
 * own screen and view model call. iOS's `ReadingListCoverMenuTests` makes the same three.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class ReadingListCoverMenuTest {

    @get:Rule
    val compose = createComposeRule()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private fun model(holding: List<String>): Pair<LibraryViewModel, UUID> {
        val viewModel = LibraryViewModel(application)
        viewModel.createList("Crossover")
        val id = viewModel.shelves.value.lists.first().id
        if (holding.isNotEmpty()) viewModel.appendToList(holding, id)
        return viewModel to id
    }

    private fun show(viewModel: LibraryViewModel, id: UUID): String {
        var name = ""
        compose.setContent {
            name = stringResource(R.string.shelves_cover)
            StoryArcTheme {
                ReadingListDetailScreen(viewModel = viewModel, id = id, onOpen = {}, onBack = {})
            }
        }
        compose.waitForIdle()
        return name
    }

    @Test
    fun `a list holding something offers the cover choice`() {
        val (viewModel, id) = model(holding = listOf("a", "b"))

        val name = show(viewModel, id)

        compose.onNodeWithContentDescription(name).assertIsDisplayed()
    }

    @Test
    fun `a list holding nothing does not offer it`() {
        val (viewModel, id) = model(holding = emptyList())

        val name = show(viewModel, id)

        compose.onNodeWithContentDescription(name).assertDoesNotExist()
    }

    @Test
    fun `the chosen cover is the one the list then wears`() {
        val (viewModel, id) = model(holding = listOf("a", "b"))

        viewModel.setListCover("b", id)

        val list = viewModel.shelves.value.lists.first()
        assertEquals("b", list.coverMemberId)
        assertEquals(ShelfCoverOption.Member("b"), ShelfCoverChoice.chosen(list))
    }
}
