package app.storyarc.feature.library

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.format.SkipReason
import app.storyarc.feature.library.SkippedPublications.Entry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The notice a screen reader speaks, in the language the reader chose
 * (`one-vocabulary-in-four-languages` 1.8).
 *
 * `SkippedNoticeTest` asserts one merged node carries the name and the reason, but its
 * locale is the default, so it cannot tell a translated reason from an English one that
 * leaked into a French notice. These two tests set the resource locale to French and to
 * English and read the merged node for the **real** [SkippedNotice], so the words a screen
 * reader would speak are the words asserted.
 *
 * What stays outside a host test: that TalkBack, on a device whose interface is French,
 * reads that node as one swipe stop. `adb shell uiautomator dump` on an emulator shows the
 * node, and a person with TalkBack confirms the speech.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SkippedNoticeLanguageTest {

    @get:Rule
    val compose = createComposeRule()

    private val sevenZip = Entry("refused.cb7", SkipReason.UnsupportedFormat("CB7"))

    private fun show() {
        compose.setContent {
            StoryArcTheme {
                SkippedNotice(
                    skipped = SkippedPublications().settling(listOf(sevenZip)),
                    onDismiss = {},
                )
            }
        }
    }

    @Test
    @Config(sdk = [34], qualifiers = "fr-w360dp-h1200dp")
    fun `in French one node holds the name and the French reason, and no English`() {
        show()

        val name = "« refused.cb7 » n’a pas pu être ouvert"
        val reason = "StoryArc ne lit pas le format CB7"
        compose.onNode(hasText(name, substring = true) and hasText(reason, substring = true))
            .assertIsDisplayed()
        compose.onAllNodesWithText(reason, substring = true).assertCountEquals(1)
        compose.onAllNodesWithText("is not a format StoryArc reads", substring = true).assertCountEquals(0)
        compose.onAllNodesWithText("couldn’t be opened", substring = true).assertCountEquals(0)
    }

    @Test
    @Config(sdk = [34], qualifiers = "w360dp-h1200dp")
    fun `in English the same node holds the English reason`() {
        show()

        val name = "“refused.cb7” couldn’t be opened"
        val reason = "CB7 is not a format StoryArc reads"
        compose.onNode(hasText(name, substring = true) and hasText(reason, substring = true))
            .assertIsDisplayed()
        compose.onAllNodesWithText("ne lit pas le format", substring = true).assertCountEquals(0)
    }
}
