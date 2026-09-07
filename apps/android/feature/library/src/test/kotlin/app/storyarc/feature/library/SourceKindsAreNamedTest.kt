package app.storyarc.feature.library

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.speaking
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The four kinds of place are named, with a line each saying what they are.
 *
 * `sources`' *Adding the first source* asks for "an empty state naming the four source types
 * with a one-line explanation of each", and the live delta puts that naming one level down:
 * "the four source types are named only after that secondary action is taken, where choosing
 * between them is the question being asked".
 *
 * **The eight strings existed, in four languages, and nothing drew them.**
 * [SourceKind.titleRes] and [SourceKind.explanationRes] had no caller anywhere in the app. Both
 * menus labelled their rows with the four *sheets'* titles instead, which name the destination
 * and say nothing about what it is. This was the tenth piece of dead code found in this area.
 *
 * **The tree is asked, not the source.** Robolectric composes the real menu, so what a reader
 * would see can be read back: a row inside a `DropdownMenu` is composed only while the menu is
 * open, which is why every assertion below follows a press. iOS's `SourceKindsAreNamedTests`
 * walks its own menu's body for the same eight keys.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SourceKindsAreNamedTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun string(id: Int): String = context.getString(id)

    private fun open(content: @Composable () -> Unit, label: String) {
        compose.setContent { StoryArcTheme { content() } }
        compose.onNodeWithContentDescription(label).performClick()
    }

    /** The toolbar's way in: an icon button carrying the same five choices. */
    private fun openToolbarMenu() = open(
        content = { AddSourceMenu(onAddFolder = {}, onAddCatalogue = {}) },
        label = string(R.string.library_add_source),
    )

    /** The empty state's plain secondary action, which `sources` names in so many words. */
    private fun openEmptyStateMenu() {
        compose.setContent {
            StoryArcTheme {
                EmptyLibrary(
                    onOpenComic = {},
                    onAddFolder = {},
                    onAddCatalogue = {},
                    onAddKavita = {},
                    onAddShare = {},
                )
            }
        }
        compose.onNodeWithText(string(R.string.library_add_source)).performClick()
    }

    /**
     * Home's first run, which is the same empty state and not a copy of it.
     *
     * A first launch lands here, so this is the only surface that reader sees. Home used to
     * draw its own two-action state and name no source kind at all.
     */
    private fun openHomeFirstRunMenu() {
        compose.setContent {
            StoryArcTheme {
                HomeScreen(
                    surface = HomeSurface(),
                    cover = { _, _ -> null },
                    onOpen = {},
                    onResume = {},
                    onFinish = {},
                    onShowAll = {},
                    onOpenFile = {},
                    onAddFolder = {},
                    onAddCatalogue = {},
                    onAddKavita = {},
                    onAddShare = {},
                )
            }
        }
        compose.onNodeWithText(string(R.string.library_add_source)).performClick()
    }

    @Test
    fun `the toolbar menu names each of the four kinds`() {
        openToolbarMenu()
        for (kind in SourceKind.entries) {
            compose.onNodeWithText(string(kind.titleRes)).assertIsDisplayed()
        }
    }

    @Test
    fun `the toolbar menu explains each of the four kinds`() {
        openToolbarMenu()
        for (kind in SourceKind.entries) {
            compose.onNodeWithText(string(kind.explanationRes)).assertIsDisplayed()
        }
    }

    @Test
    fun `the empty state's secondary action names and explains the same four`() {
        // The surface the delta names: "the surface that names the four is the library
        // destination's own empty state". Two menus for one job is how one of them ends up a
        // row short, so both are asked for the same eight lines.
        openEmptyStateMenu()
        for (kind in SourceKind.entries) {
            compose.onNodeWithText(string(kind.titleRes)).assertIsDisplayed()
            compose.onNodeWithText(string(kind.explanationRes)).assertIsDisplayed()
        }
    }

    @Test
    fun `home's first run names and explains the same four`() {
        // Reversed on 2026-09-07: home draws the library's empty state rather than a state of
        // its own. A reader with a Kavita server had to guess that a second destination held
        // what they came for, because home named a file and a folder and nothing else.
        openHomeFirstRunMenu()
        for (kind in SourceKind.entries) {
            compose.onNodeWithText(string(kind.titleRes)).assertIsDisplayed()
            compose.onNodeWithText(string(kind.explanationRes)).assertIsDisplayed()
        }
    }

    @Test
    fun `the import keeps its own row beside the four`() {
        // `local-library` gives an imported copy a requirement of its own, and "On this
        // device" is not a place a reader configures. It keeps its own words and takes no
        // source-kind line.
        openToolbarMenu()
        compose.onNodeWithText(string(R.string.library_import)).assertIsDisplayed()
    }

    @Test
    fun `every title and every explanation is written in all four languages`() {
        for (tag in listOf("en", "fr", "de", "es")) {
            val reader = context.speaking(tag)
            for (kind in SourceKind.entries) {
                val title = reader.getString(kind.titleRes)
                val explanation = reader.getString(kind.explanationRes)
                assertTrue("$kind has no title in $tag", title.isNotBlank())
                assertTrue("$kind has no explanation in $tag", explanation.isNotBlank())
                assertNotEquals(
                    "$kind's title and explanation are the same line in $tag",
                    title,
                    explanation,
                )
            }
        }
    }
}
