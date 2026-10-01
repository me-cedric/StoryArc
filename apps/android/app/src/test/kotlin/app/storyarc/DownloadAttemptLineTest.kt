package app.storyarc

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Download
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The download row says whether the last attempt resumed or restarted (6.7).
 *
 * `offline-downloads`' *Resuming after interruption* builds both outcomes and told the
 * reader neither. `OpdsClient.download` and `DownloadQueue` now record which one happened;
 * this pins that the row reads the record and draws the right sentence, in the reader's own
 * words.
 *
 * `GraphicsMode.NATIVE` for the reason `DownloadsSayWhatIsTrueTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class DownloadAttemptLineTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a resumed download says so`() {
        showRow(download(lastAttempt = Download.LastAttempt.RESUMED))
        compose.onNodeWithText(string(R.string.downloads_attempt_resumed)).assertIsDisplayed()
    }

    @Test
    fun `a restarted download says so`() {
        showRow(download(lastAttempt = Download.LastAttempt.RESTARTED))
        compose.onNodeWithText(string(R.string.downloads_attempt_restarted)).assertIsDisplayed()
    }

    @Test
    fun `a download on its first try says neither`() {
        // The other half of the claim: a row drawn for every download, whatever it is
        // doing, is no information at all -- and on a first try it would be false either
        // way.
        showRow(download(lastAttempt = null))

        assertEquals(
            "a first-try row drew an attempt sentence",
            0,
            compose.onAllNodesWithText(string(R.string.downloads_attempt_resumed))
                .fetchSemanticsNodes().size +
                compose.onAllNodesWithText(string(R.string.downloads_attempt_restarted))
                    .fetchSemanticsNodes().size,
        )
    }

    private fun showRow(download: Download) = compose.setContent {
        StoryArcTheme {
            DownloadQueueRow(
                download = download,
                canReorder = false,
                onReorder = {},
                onPause = {},
                onResume = {},
                onStop = {},
                onRetry = {},
            )
        }
    }

    private fun string(id: Int): String =
        ApplicationProvider.getApplicationContext<Context>().getString(id)

    private fun download(lastAttempt: Download.LastAttempt?) = Download(
        id = "one",
        title = "Harbour Lights 03",
        remote = "https://example.invalid/hl03.epub",
        mediaType = "application/epub+zip",
        state = Download.State.Running,
        expectedBytes = 8_400_000,
        downloadedBytes = 3_100_000,
        lastAttempt = lastAttempt,
    )
}
