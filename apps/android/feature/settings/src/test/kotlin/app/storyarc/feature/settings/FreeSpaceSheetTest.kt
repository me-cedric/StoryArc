package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.RemovedDownload
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The free-space sheet behind the storage-full hold (6.6): a largest-first list of finished
 * downloads, each removable, with the same ten-second undo every other removal offers.
 *
 * The group is composed, not read as text, for the reason `DownloadsHeldNoteTest` gives: a
 * row left behind a comment satisfies a text match and fails a reader. iOS answers the same
 * claims in `FreeSpaceSheetTests.swift` by walking the view's own value tree; here the real
 * composition is measured and tapped, because Robolectric can.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class FreeSpaceSheetTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun download(id: String, bytes: Long) = Download(
        id = id,
        title = id,
        remote = "file:///nowhere/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = Download.State.Finished,
        downloadedBytes = bytes,
    )

    /**
     * A [RemovedDownload] nothing in this test ever settles or undoes for real: this suite
     * asserts that `FreeSpaceContent` calls `onRemove`/`onRestore`, not what a real
     * implementation of either does once called. `FinishedCleanupTest` already proves the
     * real one, on both platforms.
     */
    private fun removedDownload(download: Download) = RemovedDownload(
        download = download,
        aside = File(context.filesDir, "${download.id}.removing"),
        store = DownloadStore.open(context),
    )

    private fun isDrawn(text: String): Boolean =
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun `the biggest finished download is drawn before the smallest`() {
        compose.setContent {
            StoryArcTheme {
                Column {
                    FreeSpaceContent(
                        downloads = DownloadLibrary(
                            listOf(download("small", bytes = 1_000), download("large", bytes = 9_000)),
                        ),
                        onRemove = { null },
                        onRestore = {},
                    )
                }
            }
        }
        compose.waitForIdle()

        val largeTop = compose.onNodeWithText("large").fetchSemanticsNode().boundsInRoot.top
        val smallTop = compose.onNodeWithText("small").fetchSemanticsNode().boundsInRoot.top

        assertTrue("large ($largeTop) should be above small ($smallTop)", largeTop < smallTop)
    }

    @Test
    fun `removing a row calls onRemove and offers an undo naming it`() {
        val removedCalls = mutableListOf<Download>()
        val one = download("one", bytes = 512_000L)

        compose.setContent {
            StoryArcTheme {
                Column {
                    FreeSpaceContent(
                        downloads = DownloadLibrary(listOf(one)),
                        onRemove = { removedCalls.add(it); removedDownload(it) },
                        onRestore = {},
                    )
                }
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(
            context.getString(R.string.downloads_remove_action, "one"),
        ).performClick()
        compose.waitForIdle()

        assertEquals(listOf(one), removedCalls)
        compose.onNodeWithText(context.getString(R.string.downloads_removed, "one")).assertExists()
        assertFalse("the removed row is gone", isDrawn(context.getString(R.string.downloads_remove_action, "one")))
    }

    @Test
    fun `undoing a removal calls onRestore and the row comes back`() {
        val restoredCalls = mutableListOf<RemovedDownload>()
        val one = download("one", bytes = 512_000L)

        compose.setContent {
            StoryArcTheme {
                Column {
                    FreeSpaceContent(
                        downloads = DownloadLibrary(listOf(one)),
                        onRemove = { removedDownload(it) },
                        onRestore = { restoredCalls.add(it) },
                    )
                }
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(
            context.getString(R.string.downloads_remove_action, "one"),
        ).performClick()
        compose.waitForIdle()

        compose.onNodeWithText(context.getString(R.string.downloads_undo)).performClick()
        compose.waitForIdle()

        assertEquals(1, restoredCalls.size)
        assertEquals("one", restoredCalls.single().download.id)
        assertFalse(
            "the undo row settles once restored",
            isDrawn(context.getString(R.string.downloads_removed, "one")),
        )
    }

    @Test
    fun `nothing has been removed when the sheet first opens`() {
        // `removed` starts null; the undo row draws only after a tap. A sheet that opens
        // already announcing a removal would mislead before the reader has touched anything.
        compose.setContent {
            StoryArcTheme {
                Column {
                    FreeSpaceContent(
                        downloads = DownloadLibrary(listOf(download("one", bytes = 512_000L))),
                        onRemove = { null },
                        onRestore = {},
                    )
                }
            }
        }
        compose.waitForIdle()

        assertFalse(isDrawn(context.getString(R.string.downloads_undo)))
    }
}
