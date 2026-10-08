package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.CertificatePinNotice
import app.storyarc.core.model.ImportPreviewLine
import app.storyarc.core.model.ImportedShelf
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `library-portability` tasks 2.3, 3.3 and 6.8: each line the preview can draw. iOS's
 * `ImportPreviewLineViewTests` asserts the same rows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class ImportPreviewLineRowsTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun string(id: Int, vararg args: Any) = context.getString(id, *args)

    private fun plural(id: Int, count: Int) = context.resources.getQuantityString(id, count, count)

    private fun isDrawn(text: String) =
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun show(line: ImportPreviewLine) {
        compose.setContent { StoryArcTheme { Column { ImportPreviewLineRows(line) } } }
        compose.waitForIdle()
    }

    @Test
    fun `the pin line is flagged as a change to what the app trusts and says why`() {
        show(ImportPreviewLine.CertificatePins(listOf(CertificatePinNotice("nas.local", "Comics NAS"))))

        assertTrue(isDrawn(string(R.string.transfer_line_pins)))
        assertTrue(isDrawn(string(R.string.transfer_line_pins_note)))
    }

    @Test
    fun `a pin row names the host and the source it arrived with or says there is none`() {
        show(
            ImportPreviewLine.CertificatePins(
                listOf(CertificatePinNotice("nas.local", "Comics NAS"), CertificatePinNotice("evil.example", null)),
            ),
        )

        assertTrue(isDrawn(string(R.string.transfer_line_pin, "nas.local", "Comics NAS")))
        assertTrue(isDrawn(string(R.string.transfer_line_pin_alone, "evil.example")))
    }

    @Test
    fun `the merge line counts the shelves and each row says how many members it gains`() {
        show(ImportPreviewLine.ShelvesMerged(listOf(ImportedShelf("Image Comics", 3), ImportedShelf("Crossover", 1))))

        assertTrue(isDrawn(plural(R.plurals.transfer_line_merged, 2)))
        assertTrue(isDrawn("Image Comics"))
        assertTrue(isDrawn(plural(R.plurals.transfer_line_merged_added, 3)))
        assertTrue(isDrawn(plural(R.plurals.transfer_line_merged_added, 1)))
    }

    @Test
    fun `sources, sign-ins and shelves each look up their own sentence and list their names`() {
        show(ImportPreviewLine.SourcesToAdd(listOf("Comics NAS", "Kavita")))
        assertTrue(isDrawn(plural(R.plurals.transfer_line_sources, 2)))
        assertTrue(isDrawn("Kavita"))
    }

    @Test
    fun `progress says what is added and what is merged and leaves out a count of zero`() {
        show(ImportPreviewLine.Progress(add = 0, merge = 1))

        assertTrue(isDrawn(plural(R.plurals.transfer_line_progress_merge, 1)))
        assertFalse(isDrawn(plural(R.plurals.transfer_line_progress_add, 0)))
    }

    @Test
    fun `nothing new and a settings change are each a sentence`() {
        show(ImportPreviewLine.NothingNew)
        assertTrue(isDrawn(string(R.string.transfer_line_nothing)))
    }

    @Test
    fun `the settings line is a sentence`() {
        show(ImportPreviewLine.SettingsChange)
        assertTrue(isDrawn(string(R.string.transfer_line_settings)))
    }

    @Test
    fun `themes and covers are counted`() {
        compose.setContent {
            StoryArcTheme {
                Column {
                    ImportPreviewLineRows(ImportPreviewLine.Themes(2))
                    ImportPreviewLineRows(ImportPreviewLine.Covers(1))
                }
            }
        }
        compose.waitForIdle()

        assertTrue(isDrawn(plural(R.plurals.transfer_line_themes, 2)))
        assertTrue(isDrawn(plural(R.plurals.transfer_line_covers, 1)))
    }
}
