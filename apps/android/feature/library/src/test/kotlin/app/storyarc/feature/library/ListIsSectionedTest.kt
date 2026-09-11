package app.storyarc.feature.library

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.Locale

/**
 * A long list is divided, and its index still lands on the row it names.
 *
 * `library-browsing`'s *Sectioning a long library* says "the library", not "the grid". The list
 * drew no heading at any length: a shelf of 218 publications drew two pinned headings in the
 * grid and none in the list on an Android emulator on 2026-09-11.
 *
 * The second test is the trap that came with the fix. [CoverList] moves the list by an **item**
 * index, and a heading is an item, so a publication's own position on the shelf stops being its
 * target the moment the list divides. The shelf here holds four items per section, so the letter
 * *S* sits at item 73 while the publication sits at position 54 — far enough apart that a jump
 * to the wrong one of the two shows no *S* row at all.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ListIsSectionedTest {

    @get:Rule
    val compose = createComposeRule()

    private val viewModel by lazy {
        LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
    }

    private val english = Locale.forLanguageTag("en-US")

    private fun string(id: Int, vararg args: Any): String =
        ApplicationProvider.getApplicationContext<Context>().getString(id, *args)

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.EMBEDDED,
    )

    /** Seventy-eight rows over twenty-six initials, already in the shelf's own order. */
    private val shelf = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".flatMap { letter ->
        (1..3).map { publication("${letter}ldbury Hall $it") }
    }

    /** One column, because this is the list. The grid refuses this division. */
    private val sections =
        LibrarySections.divide(shelf, LibrarySort.TITLE, "Other", english, columns = 1)

    private val rail = LibraryRail.of(shelf, LibrarySort.TITLE, english)

    @Test
    fun `a divided list draws a heading over each section`() {
        // Drawn without the rail, so the only node reading a bare letter is a heading. The rail
        // draws the same twenty-six letters, and the test below is the one that presses them.
        assertEquals(26, sections.size)
        compose.setContent {
            StoryArcTheme {
                CoverList(
                    publications = shelf,
                    viewModel = viewModel,
                    onOpen = {},
                    sections = sections,
                )
            }
        }

        compose.onNodeWithText("A").assertExists()
    }

    @Test
    fun `a letter lands on its own row, counting the headings in the way`() {
        // The two numbers the fix is about, stated before the list is drawn: where *S* sits on
        // the shelf, and where it sits among the items.
        assertEquals(54, shelf.indexOfFirst { it.displayTitle == "Sldbury Hall 1" })
        val targets = LibraryRail.itemIndexes(shelf, sections, leading = 0)
        assertEquals(73, targets[shelf[54].id])

        compose.setContent {
            StoryArcTheme {
                CoverList(
                    publications = shelf,
                    viewModel = viewModel,
                    onOpen = {},
                    sections = sections,
                    rail = rail,
                )
            }
        }

        compose.onNodeWithContentDescription(string(R.string.library_index_jump, "S")).performClick()

        compose.onNodeWithText("Sldbury Hall 1").assertIsDisplayed()
    }
}
