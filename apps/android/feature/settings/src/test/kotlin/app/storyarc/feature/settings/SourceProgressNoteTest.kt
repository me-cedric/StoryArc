package app.storyarc.feature.settings

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.ImportedCopies
import org.junit.Assert.assertTrue
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
 * assertion about what a reader sees. It is also what makes the last four tests mean
 * anything: they measure the sentence at the largest text size in the narrowest window, and
 * legacy measurement would fit any string anywhere.
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

    /**
     * The screen as `SettingsScreen` reaches it, for one source.
     *
     * Returns the sentence so the assertions look for the shipped string in the locale
     * Robolectric was configured with, rather than for a copy of it written into this file.
     */
    private fun show(source: Source, fontScale: Float = 1f): String {
        var sentence = ""
        compose.setContent {
            sentence = stringResource(R.string.sources_detail_progress_local_only)
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = fontScale),
            ) {
                StoryArcTheme {
                    SourceDetailScreen(
                        source = source,
                        // The real value the screen is given, so the note is placed among the
                        // fields it actually shares the column with.
                        diagnosis = SourceDiagnosis.of(
                            source,
                            itemCount = 3,
                            downloads = emptyList(),
                            isRemovable = source.id != ImportedCopies.SOURCE_ID,
                        ),
                        onAction = {},
                        onBack = {},
                    )
                }
            }
        }
        compose.waitForIdle()
        return sentence
    }

    private fun show(kind: SourceKind, fontScale: Float = 1f): String =
        show(Source(displayName = "Fixture", kind = kind, state = SourceConnectionState.Connected), fontScale)

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

    @Test
    fun `on this device does not, because it is the device`() {
        // `ImportedCopies` registers "On this device" as a real source of kind LOCAL_FOLDER
        // the moment a reader imports a file, and `SourcesGroup` makes every row in Your
        // libraries open its detail screen. On the kind alone the sentence renders here and
        // tells a reader that the device cannot store progress and that their place is kept
        // on the device: a category error and a tautology, two lines apart.
        val device = Source(
            id = ImportedCopies.SOURCE_ID,
            displayName = "On this device",
            kind = SourceKind.LOCAL_FOLDER,
            state = SourceConnectionState.Connected,
        )
        compose.onNodeWithText(show(device)).assertDoesNotExist()
    }

    // The sentence is the longest string on this screen and the only one that has to wrap, so
    // `design.md` §3 and §10 -- every screen survives the largest accessibility text size with
    // "no clipping" -- lands on it harder than on the fields above. All four shipped locales,
    // because the length that decides the wrap is different in each and guessing which one is
    // the worst case is how a sibling row's notes got their numbers wrong twice.

    @Test
    @Config(qualifiers = "w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in English`() =
        assertTheNoteFitsTheGutter()

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in German`() =
        assertTheNoteFitsTheGutter()

    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in Spanish`() =
        assertTheNoteFitsTheGutter()

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in French`() =
        assertTheNoteFitsTheGutter()

    private fun assertTheNoteFitsTheGutter() {
        val sentence = show(SourceKind.NETWORK_SHARE, fontScale = LARGEST_TEXT)
        val bounds = compose.onNodeWithText(sentence).getUnclippedBoundsInRoot()
        // Unclipped bounds, so a sentence laid out past the edge reports where it really went
        // rather than where the window cut it. The screen pads its scrolling column by the
        // gutter on every side, so those two edges are the ones a wrap has to respect.
        assertTrue("the note was measured ${bounds.right - bounds.left} wide",
            bounds.right - bounds.left > Dp.Hairline)
        assertTrue("the note starts at ${bounds.left}", bounds.left >= StoryArcSpace.gutter)
        assertTrue(
            "the note ends at ${bounds.right}, past ${WINDOW - StoryArcSpace.gutter}",
            bounds.right <= WINDOW - StoryArcSpace.gutter,
        )
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
