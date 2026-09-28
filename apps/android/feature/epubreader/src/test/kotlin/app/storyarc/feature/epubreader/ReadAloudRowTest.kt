package app.storyarc.feature.epubreader

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A publication with nothing to say offers no way to say it.
 *
 * `ebook-reader`, *A publication with nothing to say*:
 *
 * > **WHEN** a publication carries no text that can be extracted
 * > **THEN** the read-aloud control is absent rather than present and refusing
 *
 * Nothing asserted this on either platform. `SpokenSentences.isSpeakable` decides the answer
 * and `EpubReaderActivity` carries it into [EpubMenuFacts.canReadAloud]; what was never
 * checked is the last step — that a false answer removes the row instead of disabling it.
 *
 * **An absence can only be read in a tree**, so the menu is composed. The rows are composed
 * without their `ModalBottomSheet`: a modal sheet opens a window of its own and animates into
 * it, and none of that is the rule under test. [EpubMenuBody] is that lift.
 *
 * Both directions are asserted. A menu that had stopped drawing the row for any reason would
 * pass the absence on its own, which is the shape of a check that cannot fail.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37; 34 is above the app's minimum.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class ReadAloudRowTest {

    @get:Rule
    val compose = createComposeRule()

    private var started = 0
    private var stopped = 0

    private fun menu(canReadAloud: Boolean, isReadingAloud: Boolean = false) {
        val facts = EpubMenuFacts(
            chapter = "Chapter Two",
            progression = 0.4,
            withinChapter = 0.5,
            isPageBookmarked = false,
            isContentsReady = true,
            canReadAloud = canReadAloud,
            isReadingAloud = isReadingAloud,
        )
        val actions = EpubMenuActions(
            onDismiss = {},
            onOpenContents = {},
            onToggleBookmark = {},
            onOpenTheme = {},
            onStartReadAloud = { started += 1 },
            onStopReadAloud = { stopped += 1 },
        )
        compose.setContent { StoryArcTheme { EpubMenuBody(facts, actions) } }
        compose.waitForIdle()
    }

    @Test
    fun `a publication with no extractable text offers no read-aloud row`() {
        menu(canReadAloud = false)

        compose.onNodeWithText("Read aloud").assertDoesNotExist()
        compose.onNodeWithText("Stop reading aloud").assertDoesNotExist()
    }

    /** The control: the same menu draws the row when there is text to say. */
    @Test
    fun `a publication with text offers the row, and it starts the voice`() {
        menu(canReadAloud = true)

        compose.onNodeWithText("Read aloud").assertIsDisplayed().performClick()

        assertEquals(1, started)
        assertEquals(0, stopped)
    }

    /** And while the voice is speaking the same row stops it. */
    @Test
    fun `a publication being read aloud offers the row that stops it`() {
        menu(canReadAloud = true, isReadingAloud = true)

        compose.onNodeWithText("Stop reading aloud").assertIsDisplayed().performClick()

        assertEquals(1, stopped)
        assertEquals(0, started)
    }
}
