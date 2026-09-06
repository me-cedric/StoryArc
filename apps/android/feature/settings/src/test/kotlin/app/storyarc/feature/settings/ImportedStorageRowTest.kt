package app.storyarc.feature.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.DownloadLibrary
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The storage group states what the imported copies weigh.
 *
 * `local-library`'s *Importing* scenario ends "**AND** the app reports the space used", and
 * `offline-downloads`' *Storage view* asks for the total "broken down by source". "On this
 * device" is a source. `LibraryViewModel.importedBytes` answered that question from the day it
 * was written and no screen on either platform read it, so the figure reached a reader only
 * inside the downloads total, under a label that says downloads.
 *
 * The group is composed, not read as text: a row left behind a comment satisfies a text match
 * and fails a reader. iOS answers the same three claims in `ImportedStorageRowTests.swift` by
 * walking the view's own value tree.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class ImportedStorageRowTest {

    @get:Rule
    val compose = createComposeRule()

    /** What the group can say about storage for one figure, as the reader would read it. */
    private data class Said(val label: String, val figure: String, val anyField: String)

    private fun show(importedBytes: Long, bytesOnDisk: Long = 129_000L): Said {
        var read = Said("", "", "")
        compose.setContent {
            read = Said(
                label = stringResource(R.string.downloads_imported),
                // The platform formatter, through the same call the group makes. A literal
                // here would assert one locale's spelling of a size rather than the row.
                figure = Formatter.formatShortFileSize(LocalContext.current, importedBytes),
                anyField = stringResource(R.string.downloads_total),
            )
            StoryArcTheme {
                Column {
                    DownloadsGroup(
                        bytesOnDisk = bytesOnDisk,
                        importedBytes = importedBytes,
                        downloads = DownloadLibrary(),
                        settings = AppSettings(),
                    )
                }
            }
        }
        compose.waitForIdle()
        return read
    }

    private fun isDrawn(text: String): Boolean =
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun `a device holding imported copies is told what they weigh`() {
        val said = show(importedBytes = 512_000L)

        compose.onNodeWithText(said.label).assertExists()
        compose.onNodeWithText(said.figure).assertExists()
    }

    @Test
    fun `the figure is written the way every other row writes one`() {
        // The platform formatter, which is what `bytesOnDisk` beside it uses. A row composing
        // its own spelling is how one figure comes to look like two.
        val said = show(importedBytes = 512_000L)

        compose.onNodeWithText(said.figure).assertExists()
    }

    @Test
    fun `a device holding no imported copies is not told about them`() {
        // The other half of the claim. A row of zero drawn for a reader who has never imported
        // a file is the noise every other conditional row in this group avoids.
        val said = show(importedBytes = 0L)

        compose.onNodeWithText(said.anyField).assertExists()
        assertFalse(isDrawn(said.label))
    }
}
