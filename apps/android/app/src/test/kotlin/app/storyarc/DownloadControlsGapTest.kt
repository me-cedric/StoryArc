package app.storyarc

import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Download
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.4 and 24.5 of `close-the-audited-gaps`: the two text buttons of a download row are 8
 * dp apart.
 *
 * *Pause* and *Stop*, or *Retry* and *Remove*, were two text buttons side by side in a plain
 * row with no space between them, which is the fault the owner found on the cover. The row is
 * composed through the function the downloads screen calls.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class DownloadControlsGapTest {

    @get:Rule
    val compose = createComposeRule()

    private fun show(state: Download.State) {
        compose.setContent {
            StoryArcTheme {
                DownloadQueueRow(
                    download = Download(
                        id = "one",
                        title = "Harbour Lights 03",
                        remote = "https://example.invalid/hl03.epub",
                        mediaType = "application/epub+zip",
                        state = state,
                        expectedBytes = 8_400_000,
                        downloadedBytes = 3_100_000,
                    ),
                    canReorder = false,
                    onReorder = {},
                    onPause = {},
                    onResume = {},
                    onStop = {},
                    onRetry = {},
                )
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun `pause and stop are 8 dp apart`() {
        show(Download.State.Running)

        compose.onAllNodes(hasClickAction()).assertTouchTargetsAreApart()
    }

    @Test
    fun `retry and remove are 8 dp apart`() {
        show(Download.State.Failed(reason = "No connection", attempts = 3))

        compose.onAllNodes(hasClickAction()).assertTouchTargetsAreApart()
    }
}
