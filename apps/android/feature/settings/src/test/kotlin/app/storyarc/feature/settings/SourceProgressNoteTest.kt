package app.storyarc.feature.settings

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The source detail screen says when a source cannot hold a reading position.
 *
 * `reading-progress`' *Source cannot store progress*: "progress is kept locally only, and the
 * source detail screen states that progress for it does not sync". Three of the four source
 * kinds have no progress mechanism, the sentence for them existed in no locale on either
 * platform, and nothing computed the condition -- so a reader who added an SMB share had
 * nothing on any screen to tell them their place lives on one device.
 *
 * Composed rather than asserted through a helper, for the reason `DownloadLimitWrapTest`
 * composes: which sources *have* a mechanism is `SourceKind.syncsReadingProgress`' answer and
 * is asserted next to it in `:core:model`, but whether this screen asks the question at all
 * can only be answered by drawing it. A test of the predicate alone stays green when the row
 * is deleted from the screen, which is the state the app was already in.
 *
 * Robolectric composes on the JVM, so this runs in `testDebugUnitTest` with no emulator.
 * `GraphicsMode.NATIVE` is here because the legacy graphics measure glyphs at roughly a pixel
 * each, and a display assertion made against a text node of the wrong size is not an
 * assertion about what a reader sees.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and the
// question here -- whether one sentence is drawn -- has no API level in it. The window is
// tall because the screen scrolls: a note below the fold is present and not displayed, and
// that distinction would make this test report the wrong thing.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SourceProgressNoteTest {

    @get:Rule
    val compose = createComposeRule()

    /** The screen as `SettingsScreen` reaches it, for one source of the given kind. */
    private fun show(kind: SourceKind): String {
        var sentence = ""
        val source = Source(
            displayName = "Fixture",
            kind = kind,
            state = SourceConnectionState.Connected,
        )
        compose.setContent {
            sentence = stringResource(R.string.sources_detail_progress_local_only)
            StoryArcTheme {
                SourceDetailScreen(
                    source = source,
                    // The real value the screen is given, so the note is placed among the
                    // fields it actually shares the column with.
                    diagnosis = SourceDiagnosis.of(source, itemCount = 3, downloads = emptyList()),
                    onAction = {},
                    onBack = {},
                )
            }
        }
        compose.waitForIdle()
        return sentence
    }

    @Test
    fun `a folder says that a position stays on this device`() {
        compose.onNodeWithText(show(SourceKind.LOCAL_FOLDER)).assertIsDisplayed()
    }

    @Test
    fun `a share on the network says it too`() {
        // The kind the gap cost most: a share is a server the reader signed in to, which is
        // exactly the shape of a source they would expect to carry their place across
        // devices. It cannot -- an SMB share is files on a disk.
        compose.onNodeWithText(show(SourceKind.NETWORK_SHARE)).assertIsDisplayed()
    }

    @Test
    fun `an OPDS catalogue says it too`() {
        compose.onNodeWithText(show(SourceKind.OPDS_CATALOG)).assertIsDisplayed()
    }

    @Test
    fun `kavita does not, because for kavita it would be false`() {
        // The other half of the claim. A sentence shown on every source would be no
        // information at all, and on the one source that does sync it would be a lie.
        compose.onNodeWithText(show(SourceKind.KAVITA_SERVER)).assertDoesNotExist()
    }
}
