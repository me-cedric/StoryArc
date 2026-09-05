package app.storyarc.feature.settings

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Download
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRemovalWording
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The removal dialog's sentence follows [SourceRemovalWording], with a download and without.
 *
 * `SourceRemovalWordingTest` pins which sentence the rule picks; nothing pinned that the dialog
 * *asks* the rule. On 2026-09-05 a reviewer reverted the dialog to the plain titles-only body
 * and every automated test on both platforms stayed green, which is the gap this closes: the
 * screen is composed as `SettingsScreen` reaches it, *Remove* is pressed, and the sentence on
 * the dialog is the one the rule wrote for that diagnosis — the download named and its size
 * spelled the way the *Downloaded* row spells it. iOS asks the same of
 * `SourceDetail.confirmationMessage` in `SourceDetailSizeTests`.
 */
@RunWith(RobolectricTestRunner::class)
// 34 for the reason `SourceProgressNoteTest` gives: Robolectric has no image for 37.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
class SourceRemovalDialogTest {

    @get:Rule
    val compose = createComposeRule()

    private val share = Source(
        displayName = "Attic NAS",
        kind = SourceKind.NETWORK_SHARE,
        state = SourceConnectionState.Connected,
    )

    /** One finished download the share produced, so the diagnosis counts it. */
    private val landed = Download(
        id = "attic/harbour-lights-03",
        sourceId = share.id,
        title = "Harbour Lights 03",
        remote = "smb://attic/comics/harbour-lights-03.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = Download.State.Finished,
        downloadedBytes = 2_048,
    )

    /**
     * Composes the screen for [share] holding [downloads], presses *Remove*, and returns the two
     * sentences the rule can write — the one for this diagnosis first, the titles-only one
     * second — resolved inside the one composition (a second `setContent` fails under this
     * rule, as `SourceRemovalFooterTest` records) and in Robolectric's locale rather than as a
     * copy written into this file.
     */
    private fun pressRemove(downloads: List<Download>): Pair<String, String> {
        val diagnosis = SourceDiagnosis.of(share, itemCount = 3, downloads = downloads)
        val bare = SourceDiagnosis.of(share, itemCount = 3, downloads = emptyList())
        var expected = ""
        var plain = ""
        var remove = ""
        compose.setContent {
            expected = removalBody(SourceRemovalWording.of(diagnosis))
            plain = removalBody(SourceRemovalWording.of(bare))
            remove = stringResource(R.string.sources_remove)
            StoryArcTheme {
                SourceDetailScreen(source = share, diagnosis = diagnosis, onAction = {}, onBack = {})
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText(remove).performClick()
        compose.waitForIdle()
        return expected to plain
    }

    @Test
    fun `a source holding a download is asked about the download and its size`() {
        val (sentence, plain) = pressRemove(listOf(landed))
        // The two sentences must differ, or the assertion below could not tell them apart.
        assertNotEquals(plain, sentence)
        compose.onNodeWithText(sentence).assertIsDisplayed()
        compose.onNodeWithText(plain).assertDoesNotExist()
    }

    @Test
    fun `a source holding nothing is asked about its titles alone`() {
        val (sentence, plain) = pressRemove(emptyList())
        assertEquals(plain, sentence)
        compose.onNodeWithText(sentence).assertIsDisplayed()
    }
}
