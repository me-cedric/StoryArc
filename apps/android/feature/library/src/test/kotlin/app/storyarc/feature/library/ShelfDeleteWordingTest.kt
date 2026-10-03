package app.storyarc.feature.library

import android.app.Application
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `one-vocabulary-in-four-languages` 4.1/task 15.11: `ShelfCard`'s delete menu item used to
 * carry the shelf's name, because it shared one string resource with the long-press
 * accessibility label a screen reader needs the name for. iOS's own menu item names nothing
 * -- the confirmation dialog that follows already states the shelf in its title -- and
 * `shelves_delete` now agrees, through `shelves_delete_action` carrying the name instead.
 *
 * 34 for the reason `ShelfDeletionDialogTest` gives: Robolectric has no image for 37.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class ShelfDeleteWordingTest {

    @get:Rule
    val compose = createComposeRule()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `the delete menu item names nothing, the way iOS's does`() {
        val viewModel = LibraryViewModel(application)
        var menuLabel = ""
        compose.setContent {
            menuLabel = stringResource(R.string.shelves_delete)
            StoryArcTheme {
                ShelfCard(
                    viewModel = viewModel,
                    title = "Image Comics",
                    subtitle = "4 titles",
                    tiles = listOf("a", "b"),
                    onOpen = {},
                    onDelete = {},
                )
            }
        }
        compose.onRoot().performTouchInput { longClick() }
        compose.waitForIdle()

        compose.onNodeWithText(menuLabel).assertIsDisplayed()
    }
}
