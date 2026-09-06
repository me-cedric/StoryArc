package app.storyarc.feature.library

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What the deletion dialogue says, and what pressing its two buttons does.
 *
 * `ShelfDeletionTest` pins that applying a deletion keeps every publication; nothing pinned that
 * the dialogue *says so*. `SourceRemovalDialogTest` records why that gap matters: on 2026-09-05 a
 * reviewer reverted a removal dialog to a plainer body and every automated test on both platforms
 * stayed green.
 *
 * The sentences are resolved inside the one composition, in Robolectric's locale, rather than
 * copied into this file -- so a catalogue that lost a key fails here rather than passing against a
 * copy. iOS asks the same of `ShelfDeletion.message` in `ShelfDeletionTests`.
 */
@RunWith(RobolectricTestRunner::class)
// 34 for the reason `SourceRemovalDialogTest` gives: Robolectric has no image for 37.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
class ShelfDeletionDialogTest {

    @get:Rule
    val compose = createComposeRule()

    private val collection = PublicationCollection(
        name = "Reading soon",
        members = setOf("a", "b", "c"),
    )

    private val list = ReadingList(name = "Crossover", entries = listOf("a", "c"))

    @Test
    fun `the confirmation names the collection and says the titles stay`() {
        var title = ""
        var body = ""
        compose.setContent {
            title = stringResource(R.string.shelves_delete_title, collection.name)
            body = stringResource(R.string.shelves_delete_collection_body)
            StoryArcTheme {
                ShelfDeletionDialog(ShelfDeletion.of(collection), onConfirm = {}, onDismiss = {})
            }
        }
        compose.waitForIdle()

        compose.onNodeWithText(title).assertIsDisplayed()
        compose.onNodeWithText(body).assertIsDisplayed()
    }

    @Test
    fun `a reading list is asked about in its own words`() {
        var forList = ""
        var forCollection = ""
        compose.setContent {
            forList = stringResource(R.string.shelves_delete_list_body)
            forCollection = stringResource(R.string.shelves_delete_collection_body)
            StoryArcTheme {
                ShelfDeletionDialog(ShelfDeletion.of(list), onConfirm = {}, onDismiss = {})
            }
        }
        compose.waitForIdle()

        // The two sentences must differ, or the assertions below could not tell them apart.
        assertNotEquals(forCollection, forList)
        compose.onNodeWithText(forList).assertIsDisplayed()
        compose.onNodeWithText(forCollection).assertDoesNotExist()
    }

    /** Cancelling answers the question with a no, and nothing is written. */
    @Test
    fun `cancelling confirms nothing`() {
        var confirmed = false
        var dismissed = false
        var cancel = ""
        compose.setContent {
            cancel = stringResource(R.string.shelves_cancel)
            StoryArcTheme {
                ShelfDeletionDialog(
                    ShelfDeletion.of(collection),
                    onConfirm = { confirmed = true },
                    onDismiss = { dismissed = true },
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText(cancel).performClick()
        compose.waitForIdle()

        assertFalse(confirmed)
        assertTrue(dismissed)
    }
}
