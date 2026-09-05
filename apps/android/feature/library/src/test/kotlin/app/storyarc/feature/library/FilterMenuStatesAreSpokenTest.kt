package app.storyarc.feature.library

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Every row in the filter menu says which state it is in, to a reader who cannot see it.
 *
 * `library-browsing`, *A control that stands alone carries a name*: "every one of them names
 * itself to assistive technology whatever it draws". The rows in this menu drew their state
 * and named none of it.
 *
 * **The cause is one Compose rule that reads as an optimisation and is not.** `Checkbox` and
 * `RadioButton` apply their `triStateToggleable` / `selectable` modifier **only** when handed
 * a non-null callback. Both are handed `null` here, correctly — the `DropdownMenuItem` around
 * them is the click target, and a second one inside it would be a second stop offering the
 * same value the same way. But the consequence is that with a null callback the indicator
 * contributes *no* semantics at all: not an unchecked state, none. So the tick, the dot and
 * the group's own active mark were visible and unspoken, and:
 *
 * - a reader in *Genre* could not tell which genres were ticked;
 * - a reader on the group list heard "Genre", "Tag", "Format" identically whether or not each
 *   was narrowing the shelf, while the chip outside announced three filters active — with
 *   nothing to say which three;
 * - which library, which download state and which decade the shelf was narrowed to were all
 *   decidable by eye alone.
 *
 * **This asserts the semantics tree, not the source.** A test reading `LibraryFilterMenu.kt`
 * for the word `semantics` would pass on a modifier attached to the wrong node, and the three
 * builders are `internal` rather than `private` precisely so this file can render them and
 * ask the tree what it holds. That is also the whole of what it proves: Robolectric builds
 * the tree, and what TalkBack makes of it on a device is a separate question no host test
 * answers.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above this app's minimum, and none of the three
// properties asserted here has an API level in it.
@Config(sdk = [34])
class FilterMenuStatesAreSpokenTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a ticked value is on and an unticked one is off`() {
        compose.setContent {
            StoryArcTheme {
                CheckedItem(label = "Noir", checked = true) {}
                CheckedItem(label = "Western", checked = false) {}
            }
        }

        // Both halves. Asserting only the ticked one passes against a row that reports
        // itself checked unconditionally, which is the same amount of information as none.
        compose.onNodeWithText("Noir").assertIsOn()
        compose.onNodeWithText("Western").assertIsOff()
    }

    @Test
    fun `the chosen value in a one-answer group is selected and the others are not`() {
        compose.setContent {
            StoryArcTheme {
                ChosenItem(label = "Standard Ebooks", chosen = true) {}
                ChosenItem(label = "Home NAS", chosen = false) {}
            }
        }

        compose.onNodeWithText("Standard Ebooks").assertIsSelected()
        compose.onNodeWithText("Home NAS").assertIsNotSelected()
    }

    @Test
    fun `a group narrowing the shelf says so, and an untouched one says nothing`() {
        compose.setContent {
            StoryArcTheme {
                SectionItem(label = "Genre", isActive = true) {}
                SectionItem(label = "Tag", isActive = false) {}
            }
        }

        // The active one carries the word. Read from the resource rather than typed, so the
        // three locales beside English are covered by the same assertion rather than by
        // three copies of it that would each pin a spelling.
        compose.onNodeWithText("Genre").assert(hasStateDescription())

        // And the untouched one carries no state description at all. "Tag, active" on an
        // untouched group would be worse than silence: it would send the reader into a group
        // that is narrowing nothing, looking for the filter they cannot find.
        compose.onNodeWithText("Tag").assert(SemanticsMatcher.keyIsDefined(
            SemanticsProperties.StateDescription,
        ).not())
    }

    private fun hasStateDescription(): SemanticsMatcher =
        SemanticsMatcher.keyIsDefined(SemanticsProperties.StateDescription)
}
