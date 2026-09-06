package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadHold
import app.storyarc.core.model.DownloadLibrary
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The downloads group says why the queue is waiting, and what ends the wait.
 *
 * `offline-downloads` requires a held queue to *say* what it is waiting for, because the three
 * situations have three different remedies. `DownloadQueue.held` answered the question from the
 * day it was written and nothing on either platform drew it: a reader whose queue was waiting
 * saw a list that had simply stopped.
 *
 * Six claims. Each of the three reasons draws its own two sentences, and a queue that is not
 * held draws none of them -- a screen that explains an absent problem is the noise this row
 * exists to avoid.
 *
 * The group is composed, not read as text: a row left behind a comment satisfies a text match
 * and fails a reader. It proves the sentence is drawn under the right condition, never that the
 * pixels were legible at the largest text size. iOS answers the same six claims in
 * `DownloadsHeldNoteTests.swift` by walking the view's own value tree.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class DownloadsHeldNoteTest {

    @get:Rule
    val compose = createComposeRule()

    private fun download(id: String, state: Download.State, bytes: Long = 0) = Download(
        id = id,
        title = id,
        remote = "file:///nowhere/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
        downloadedBytes = bytes,
    )

    /** Draws the group over one library and one policy, and returns the sentences it can read. */
    private fun show(downloads: List<Download>, limit: Long? = null): Sentences {
        var read = Sentences("", "", "", "", "", "", "")
        compose.setContent {
            read = Sentences(
                waitingForWifi = stringResource(R.string.downloads_paused_waiting_for_wifi),
                waitingForWifiNote = stringResource(R.string.downloads_held_waiting_for_wifi_note),
                outOfSpace = stringResource(R.string.downloads_paused_out_of_space),
                outOfSpaceNote = stringResource(R.string.downloads_held_out_of_space_note),
                storageFull = stringResource(R.string.downloads_held_storage_full),
                storageFullNote = stringResource(R.string.downloads_held_storage_full_note),
                anyField = stringResource(R.string.downloads_total),
            )
            StoryArcTheme {
                Column {
                    DownloadsGroup(
                        bytesOnDisk = 0L,
                        downloads = DownloadLibrary(downloads),
                        settings = AppSettings(maximumDownloadBytes = limit),
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
    fun `a queue waiting for wifi says so and says it starts again by itself`() {
        val said = show(listOf(download("one", waiting)))

        compose.onNodeWithText(said.waitingForWifi).assertExists()
        compose.onNodeWithText(said.waitingForWifiNote).assertExists()
    }

    @Test
    fun `a queue held by a full device says so and says it starts again by itself`() {
        val said = show(
            listOf(download("one", Download.State.Paused(Download.Pause.OUT_OF_SPACE))),
        )

        compose.onNodeWithText(said.outOfSpace).assertExists()
        compose.onNodeWithText(said.outOfSpaceNote).assertExists()
    }

    @Test
    fun `a queue at the reader's own limit says so and names both ways out`() {
        val said = show(
            listOf(
                download("kept", Download.State.Finished, bytes = 2_000),
                download("wanted", Download.State.Queued),
            ),
            limit = 1_000,
        )

        compose.onNodeWithText(said.storageFull).assertExists()
        compose.onNodeWithText(said.storageFullNote).assertExists()
    }

    @Test
    fun `a queue that is not held says nothing about being held`() {
        // The other half of every claim above. A sentence drawn whatever the queue is doing is
        // no information at all, and on a queue that is running it is false.
        val said = show(listOf(download("one", Download.State.Running)))

        compose.onNodeWithText(said.anyField).assertExists()
        assertEquals(emptyList<String>(), said.holds.filter { isDrawn(it) })
    }

    @Test
    fun `an empty queue says nothing whatever the limit is`() {
        val said = show(emptyList(), limit = 1)

        compose.onNodeWithText(said.anyField).assertExists()
        assertEquals(emptyList<String>(), said.holds.filter { isDrawn(it) })
    }

    @Test
    fun `no two reasons share a sentence`() {
        // Three remedies, three situations. Two reasons wearing one sentence would be a stalled
        // list that explains neither, which is the state this row was built to end.
        val said = show(emptyList())

        assertEquals(DownloadHold.entries.size * 2, said.holds.toSet().size)
    }

    private val waiting = Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)

    /** The sentences this screen can draw, read from the catalogue rather than repeated here. */
    private data class Sentences(
        val waitingForWifi: String,
        val waitingForWifiNote: String,
        val outOfSpace: String,
        val outOfSpaceNote: String,
        val storageFull: String,
        val storageFullNote: String,
        val anyField: String,
    ) {
        val holds: List<String> get() = listOf(
            waitingForWifi,
            waitingForWifiNote,
            outOfSpace,
            outOfSpaceNote,
            storageFull,
            storageFullNote,
        )
    }
}
