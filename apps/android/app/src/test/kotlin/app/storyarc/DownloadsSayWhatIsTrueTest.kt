package app.storyarc

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.ImportedCopies
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The two things the Downloads destination told a reader that were not true.
 *
 * **The confirmation.** *Stop*, on a row still arriving, put up *Remove this download?* —
 * "This deletes the copy of Harbour Lights 03 on this device. Your reading position is kept,
 * and it can be downloaded again." There is no copy on the device and there is no reading
 * position. Both halves of the sentence were false.
 *
 * **The control.** A transfer that had already failed offered one action, and it was *Stop*.
 * `offline-downloads` asks a failed download for "a plain-language reason and a retry
 * action"; the row had the reason and no action but the wrong verb.
 *
 * [DownloadQueueRemovalTest] pins which question is asked. This pins that the screen asks it
 * — a pure type with no caller draws nothing, and the defect was in what was drawn.
 *
 * `GraphicsMode.NATIVE` for the reason `DownloadsCoverlessWellTest` next door gives:
 * Robolectric's legacy graphics measure a string at roughly a pixel per glyph, so text fits
 * anywhere and any assertion about it passes.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above this app's minimum.
@Config(sdk = [34])
class DownloadsSayWhatIsTrueTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * The defect, photographed: a transfer in flight is stopped, and the words say so.
     *
     * The absence is half the assertion. A dialog that showed both sentences would satisfy a
     * test that only looked for the new one, and the reported defect is precisely that the
     * removal sentence was shown where it was untrue.
     */
    @Test
    fun `stopping a transfer in flight neither deletes a copy nor keeps a position`() {
        showDialog(download(Download.State.Running))

        compose.onNodeWithText(string(R.string.downloads_stop_title)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_stop_body, TITLE)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_stop_confirm)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_remove_body, TITLE)).assertDoesNotExist()
    }

    /** A failed transfer is removed rather than stopped: it stopped by itself. */
    @Test
    fun `removing a failed transfer promises nothing about a copy`() {
        showDialog(download(FAILED))

        compose.onNodeWithText(string(R.string.downloads_remove_title)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_remove_body_unfinished, TITLE))
            .assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_stop_body, TITLE)).assertDoesNotExist()
    }

    /** The case the old string was actually written for, unchanged. */
    @Test
    fun `removing a finished download still says the copy goes and the place stays`() {
        showDialog(download(Download.State.Finished))

        compose.onNodeWithText(string(R.string.downloads_remove_title)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_remove_body, TITLE)).assertIsDisplayed()
    }

    /** And an import names the original it is not touching, as `local-library` asks. */
    @Test
    fun `removing a finished import names the original it leaves alone`() {
        showDialog(download(Download.State.Finished, sourceId = ImportedCopies.SOURCE_ID))

        compose.onNodeWithText(string(R.string.downloads_remove_body, TITLE)).assertDoesNotExist()
        // The size is formatted by the platform, so the sentence is matched on its stem
        // rather than rebuilt here — what is being pinned is which of the four it is.
        compose.onNodeWithText(TITLE, substring = true).assertIsDisplayed()
    }

    /**
     * The second defect: *Stop* was the only verb a failed row had, and it is the wrong one.
     *
     * `:feature:library`'s `DownloadBanner` already followed the rule one screen away — a
     * failed download offers a retry, one that is moving offers a stop — and the queue row
     * did not.
     */
    @Test
    fun `a failed row offers a retry and a removal, and never a stop`() {
        showRow(download(FAILED))

        compose.onNodeWithText(string(R.string.downloads_retry)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_remove)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_stop)).assertDoesNotExist()
    }

    /** And a transfer that is moving keeps the verb that fits it. */
    @Test
    fun `a running row offers a stop and no retry`() {
        showRow(download(Download.State.Running))

        compose.onNodeWithText(string(R.string.downloads_stop)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.downloads_retry)).assertDoesNotExist()
    }

    private fun showDialog(download: Download) = compose.setContent {
        StoryArcTheme { RemoveDownloadDialog(download = download, onDismiss = {}, onConfirm = {}) }
    }

    private fun showRow(download: Download) = compose.setContent {
        StoryArcTheme {
            DownloadQueueRow(
                download = download,
                canReorder = false,
                onReorder = {},
                onStop = {},
                onRetry = {},
            )
        }
    }

    private fun string(id: Int, vararg args: Any): String =
        ApplicationProvider.getApplicationContext<Context>().getString(id, *args)

    private fun download(
        state: Download.State,
        sourceId: UUID? = UUID.fromString("0f2b6a1e-1111-4111-8111-111111111111"),
    ) = Download(
        id = "one",
        sourceId = sourceId,
        title = TITLE,
        remote = "https://example.invalid/hl03.epub",
        mediaType = "application/epub+zip",
        state = state,
        expectedBytes = 8_400_000,
        downloadedBytes = 3_100_000,
    )

    private companion object {
        /** The title the September sweep photographed the wrong sentence about. */
        const val TITLE = "Harbour Lights 03"
        val FAILED = Download.State.Failed(reason = "The server did not answer in time.", attempts = 3)
    }
}
