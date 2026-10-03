package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The five ways to add a source, under Settings' own button (task 17.9).
 *
 * Moved from the library toolbar per task 1.2's own direction for where it belongs; the
 * equivalent claim the library toolbar used to hold was
 * `LibraryControlsAreNamedTest`'s "the ways to add a source share one button and are named
 * inside it", now withdrawn from there.
 */
@RunWith(RobolectricTestRunner::class)
// 34 for the reason `SourceProgressNoteTest` gives: Robolectric has no image for 37.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
class AddSourceButtonTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun string(id: Int): String = context.getString(id)

    private fun showGroup(
        onAddFolder: () -> Unit = {},
        onImport: () -> Unit = {},
        onAddCatalogue: () -> Unit = {},
        onAddKavita: () -> Unit = {},
        onAddShare: () -> Unit = {},
    ) {
        compose.setContent {
            StoryArcTheme {
                SourcesGroup(
                    sources = emptyList(),
                    itemCount = { 0 },
                    diagnose = { error("not exercised") },
                    onRemove = {},
                    onRename = { _, _ -> },
                    onAddFolder = onAddFolder,
                    onImport = onImport,
                    onAddCatalogue = onAddCatalogue,
                    onAddKavita = onAddKavita,
                    onAddShare = onAddShare,
                )
            }
        }
    }

    private fun open() {
        showGroup()
        compose.onNodeWithText(string(R.string.sources_add)).performClick()
    }

    @Test
    fun `the button is reachable over an empty list of sources`() {
        showGroup()
        compose.onNodeWithText(string(R.string.sources_add)).assertHasClickAction()
    }

    @Test
    fun `the four kinds and the import each name themselves once pressed`() {
        open()
        listOf(
            R.string.sources_add_folder,
            R.string.sources_add_catalogue,
            R.string.sources_add_kavita,
            R.string.sources_add_share,
            R.string.sources_add_import,
        ).forEach { compose.onNodeWithText(string(it)).assertIsDisplayed().assertHasClickAction() }
    }

    @Test
    fun `choosing a kind runs its own action and no other`() {
        var folder = false
        var catalogue = false
        var kavita = false
        var share = false
        var import = false
        showGroup(
            onAddFolder = { folder = true },
            onImport = { import = true },
            onAddCatalogue = { catalogue = true },
            onAddKavita = { kavita = true },
            onAddShare = { share = true },
        )
        compose.onNodeWithText(string(R.string.sources_add)).performClick()
        compose.onNodeWithText(string(R.string.sources_add_kavita)).performClick()

        assertTrue(kavita)
        assertFalse(folder)
        assertFalse(catalogue)
        assertFalse(share)
        assertFalse(import)
    }
}
